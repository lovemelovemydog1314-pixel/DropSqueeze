import Darwin
import Foundation

final class DirectoryWatcher {
    private struct FileStamp: Equatable {
        let size: Int64
        let modifiedAt: Date
    }

    private let directoryURL: URL
    private let onNewFiles: ([URL]) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounceWork: DispatchWorkItem?
    private var knownFiles: [String: FileStamp] = [:]

    init(directoryURL: URL, onNewFiles: @escaping ([URL]) -> Void) {
        self.directoryURL = directoryURL
        self.onNewFiles = onNewFiles
    }

    @discardableResult
    func start() -> Bool {
        guard source == nil else { return true }
        knownFiles = currentCandidates()

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        watcher.setEventHandler { [weak self] in self?.scheduleScan() }
        watcher.setCancelHandler { close(descriptor) }
        watcher.resume()
        source = watcher
        return true
    }

    func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        source?.cancel()
        source = nil
    }

    private func scheduleScan() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanForChanges() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func scanForChanges() {
        let current = currentCandidates()
        let changedURLs = current.compactMap { path, stamp -> URL? in
            guard knownFiles[path] != stamp else { return nil }
            return URL(fileURLWithPath: path)
        }
        knownFiles = current
        if !changedURLs.isEmpty { onNewFiles(changedURLs) }
    }

    private func currentCandidates() -> [String: FileStamp] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [:] }

        var candidates: [String: FileStamp] = [:]
        for url in entries where Self.isAutomaticCandidate(url) {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  let modifiedAt = values.contentModificationDate else { continue }
            candidates[url.path] = FileStamp(size: Int64(size), modifiedAt: modifiedAt)
        }
        return candidates
    }

    private static func isAutomaticCandidate(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        guard !name.hasSuffix("-compressed"), !name.contains("-compressed-") else { return false }
        let screenshotName = ["screen shot", "screenshot", "截屏", "屏幕快照", "屏幕截图", "屏幕截屏"]
            .contains(where: name.contains)
        let recordingName = ["screen recording", "屏幕录制", "录屏"]
            .contains(where: name.contains)
        let ext = url.pathExtension.lowercased()

        if screenshotName {
            return ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(ext)
        }
        return recordingName && ext == "mov"
    }
}
