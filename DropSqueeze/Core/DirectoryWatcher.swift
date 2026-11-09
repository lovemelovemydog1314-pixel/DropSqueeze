import CoreServices
import Foundation

enum DirectoryWatcherRetryPolicy {
    /// Wait times used between attempts to compress a file that failed for a temporary reason.
    static let delays: [TimeInterval] = [10, 60, 300]
}

struct DirectoryWatcherEvent {
    let url: URL
    /// 0 for the first delivery, 1... for automatic retries of a file that failed earlier.
    let retryAttempt: Int
}

/// Watches a folder and reports files once they look stable on disk.
///
/// A file is only reported after two consecutive scans agree on its size and modification date, so
/// half-written screenshots are not processed. If the handler reports a file back as failed for a
/// transient reason, the watcher re-delivers it after a backoff instead of forgetting about it.
@MainActor
final class DirectoryWatcher {
    /// The handler returns the URLs it could not process for a temporary reason.
    typealias Handler = ([DirectoryWatcherEvent]) async -> Set<URL>

    nonisolated static var retryDelays: [TimeInterval] { DirectoryWatcherRetryPolicy.delays }

    private struct FileStamp: Equatable {
        let size: Int64
        let modifiedAt: Date
    }

    private let directoryURL: URL
    private let rule: FolderWatchRule
    private let onNewFiles: Handler
    private let retryDelays: [TimeInterval]
    private var eventStream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private var retryWork: DispatchWorkItem?
    private var knownFiles: [String: FileStamp] = [:]
    private var pendingFiles: [String: FileStamp] = [:]
    private var retryAttempts: [String: Int] = [:]
    private var retrySchedule: [String: Date] = [:]
    private var deliveryQueue: [DirectoryWatcherEvent] = []
    private var deliveryTask: Task<Void, Never>?
    private var generation = 0
    private var scanVersion = 0
    private var initialScan: Task<[String: FileStamp], Never>?
    private var initialChangedPaths: Set<String> = []

    init(
        directoryURL: URL,
        rule: FolderWatchRule = FolderWatchRule(),
        retryDelays: [TimeInterval] = DirectoryWatcher.retryDelays,
        onNewFiles: @escaping Handler
    ) {
        self.directoryURL = directoryURL
        self.rule = rule
        self.retryDelays = retryDelays
        self.onNewFiles = onNewFiles
    }

    @discardableResult
    func start() -> Bool {
        guard eventStream == nil else { return true }
        generation += 1
        let directory = directoryURL
        let scanRule = rule
        initialScan = Task.detached(priority: .utility) {
            Self.currentCandidates(directoryURL: directory, rule: scanRule) ?? [:]
        }
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [directoryURL.path] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.handleEvent,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.75,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return false }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        eventStream = stream
        return true
    }

    func stop() {
        generation += 1
        scanVersion += 1
        initialScan?.cancel()
        initialScan = nil
        initialChangedPaths.removeAll()
        knownFiles.removeAll()
        debounceWork?.cancel()
        debounceWork = nil
        retryWork?.cancel()
        retryWork = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        deliveryQueue.removeAll()
        pendingFiles.removeAll()
        retryAttempts.removeAll()
        retrySchedule.removeAll()
        guard let eventStream else { return }
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
    }

    private static let handleEvent: FSEventStreamCallback = { _, info, _, pathsPointer, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(pathsPointer, to: NSArray.self) as? [String] ?? []
        Task { @MainActor in
            if watcher.initialScan != nil { watcher.initialChangedPaths.formUnion(paths) }
            watcher.scheduleScan()
        }
    }

    private func scheduleScan() {
        guard eventStream != nil else { return }
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.scanForChanges() }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func scanForChanges() async {
        guard eventStream != nil else { return }
        let currentGeneration = generation
        scanVersion += 1
        let version = scanVersion
        if let initialScan {
            let baseline = await initialScan.value
            guard currentGeneration == generation, version == scanVersion else { return }
            knownFiles = baseline.filter { path, _ in
                !initialChangedPaths.contains { changed in
                    path == changed || path.hasPrefix(changed.hasSuffix("/") ? changed : changed + "/")
                }
            }
            initialChangedPaths.removeAll()
            self.initialScan = nil
        }
        let directory = directoryURL
        let scanRule = rule
        let current = await Task.detached(priority: .utility) {
            Self.currentCandidates(directoryURL: directory, rule: scanRule)
        }.value
        guard currentGeneration == generation, version == scanVersion, let current else { return }
        knownFiles = knownFiles.filter { current[$0.key] != nil }
        retryAttempts = retryAttempts.filter { current[$0.key] != nil }
        retrySchedule = retrySchedule.filter { current[$0.key] != nil }
        armRetryTimer()
        pendingFiles = pendingFiles.filter { path, pendingStamp in
            guard let currentStamp = current[path] else { return false }
            return currentStamp != knownFiles[path] && currentStamp == pendingStamp
        }
        var changedURLs: [URL] = []
        for (path, stamp) in current where knownFiles[path] != stamp {
            if pendingFiles[path] == stamp {
                changedURLs.append(URL(fileURLWithPath: path))
                knownFiles[path] = stamp
                pendingFiles.removeValue(forKey: path)
            } else {
                pendingFiles[path] = stamp
            }
        }
        for url in changedURLs {
            let path = url.standardizedFileURL.path
            // A new version of the file deserves a fresh retry budget.
            retryAttempts[path] = 0
            retrySchedule.removeValue(forKey: path)
        }
        if !changedURLs.isEmpty {
            enqueue(changedURLs.map { DirectoryWatcherEvent(url: $0, retryAttempt: 0) })
        }
        if !pendingFiles.isEmpty { scheduleScan() }
    }

    // MARK: - Delivery

    private func enqueue(_ events: [DirectoryWatcherEvent]) {
        guard !events.isEmpty else { return }
        deliveryQueue.append(contentsOf: events)
        startDeliveryIfNeeded()
    }

    private func startDeliveryIfNeeded() {
        guard deliveryTask == nil, !deliveryQueue.isEmpty else { return }
        let currentGeneration = generation
        deliveryTask = Task { [weak self] in
            await self?.drainDeliveries(generation: currentGeneration)
        }
    }

    private func drainDeliveries(generation: Int) async {
        while generation == self.generation, !deliveryQueue.isEmpty {
            let batch = deliveryQueue
            deliveryQueue.removeAll(keepingCapacity: true)
            let retryURLs = await onNewFiles(batch)
            guard generation == self.generation else { return }
            scheduleRetries(for: retryURLs)
        }
        guard generation == self.generation else { return }
        deliveryTask = nil
    }

    // MARK: - Retries

    private func scheduleRetries(for urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        let now = Date()
        for url in urls {
            let path = url.standardizedFileURL.path
            let attempt = retryAttempts[path] ?? 0
            guard attempt < retryDelays.count else {
                retrySchedule.removeValue(forKey: path)
                continue
            }
            retryAttempts[path] = attempt + 1
            retrySchedule[path] = now.addingTimeInterval(retryDelays[attempt])
        }
        armRetryTimer()
    }

    private func armRetryTimer() {
        retryWork?.cancel()
        retryWork = nil
        guard let earliest = retrySchedule.values.min() else { return }
        let delay = max(0, earliest.timeIntervalSinceNow)
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.fireDueRetries() }
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func fireDueRetries() {
        guard eventStream != nil else { return }
        retryWork = nil
        let now = Date()
        let duePaths = retrySchedule.filter { $0.value <= now }.map(\.key).sorted()
        guard !duePaths.isEmpty else {
            armRetryTimer()
            return
        }
        var events: [DirectoryWatcherEvent] = []
        for path in duePaths {
            retrySchedule.removeValue(forKey: path)
            guard FileManager.default.fileExists(atPath: path) else {
                retryAttempts.removeValue(forKey: path)
                continue
            }
            events.append(DirectoryWatcherEvent(
                url: URL(fileURLWithPath: path),
                retryAttempt: retryAttempts[path] ?? 1
            ))
        }
        enqueue(events)
        armRetryTimer()
    }

    // MARK: - Scanning

    private nonisolated static func currentCandidates(directoryURL: URL, rule: FolderWatchRule) -> [String: FileStamp]? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var candidates: [String: FileStamp] = [:]
        func addCandidate(_ url: URL) {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  rule.accepts(url, size: Int64(size)),
                  let modifiedAt = values.contentModificationDate else { return }
            candidates[url.path] = FileStamp(size: Int64(size), modifiedAt: modifiedAt)
        }

        if rule.includeSubfolders {
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return nil }
            for case let url as URL in enumerator { addCandidate(url) }
        } else {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return nil }
            for url in entries { addCandidate(url) }
        }
        return candidates
    }
}
