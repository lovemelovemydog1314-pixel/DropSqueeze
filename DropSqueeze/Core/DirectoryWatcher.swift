import CoreServices
import Foundation

final class DirectoryWatcher {
    private struct FileStamp: Equatable {
        let size: Int64
        let modifiedAt: Date
    }

    private let directoryURL: URL
    private let rule: FolderWatchRule
    private let onNewFiles: ([URL]) -> Void
    private var eventStream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private var knownFiles: [String: FileStamp] = [:]
    private var pendingFiles: [String: FileStamp] = [:]

    init(directoryURL: URL, rule: FolderWatchRule = FolderWatchRule(), onNewFiles: @escaping ([URL]) -> Void) {
        self.directoryURL = directoryURL
        self.rule = rule
        self.onNewFiles = onNewFiles
    }

    @discardableResult
    func start() -> Bool {
        guard eventStream == nil else { return true }
        knownFiles = currentCandidates()
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
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
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
        debounceWork?.cancel()
        debounceWork = nil
        guard let eventStream else { return }
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
    }

    private static let handleEvent: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.scheduleScan()
    }

    private func scheduleScan() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanForChanges() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func scanForChanges() {
        let current = currentCandidates()
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
        if !changedURLs.isEmpty { onNewFiles(changedURLs) }
        if !pendingFiles.isEmpty { scheduleScan() }
    }

    private func currentCandidates() -> [String: FileStamp] {
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
            ) else { return [:] }
            for case let url as URL in enumerator { addCandidate(url) }
        } else if let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for url in entries { addCandidate(url) }
        }
        return candidates
    }
}
