import AppKit
import Combine
import Foundation

struct HistoryItem: Codable, Identifiable {
    enum Kind: String, Codable {
        case clipboardImage
        case imageFile
        case videoFile
    }

    let id: UUID
    let name: String
    let kind: Kind
    let originalBytes: Int64
    let resultBytes: Int64
    let date: Date
    let outputPath: String?

    var savedBytes: Int64 { max(0, originalBytes - resultBytes) }

    init(name: String, kind: Kind, originalBytes: Int64, resultBytes: Int64, outputPath: String? = nil) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.originalBytes = originalBytes
        self.resultBytes = resultBytes
        self.date = Date()
        self.outputPath = outputPath
    }
}

private actor FileProcessingGate {
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }
        await withCheckedContinuation { continuation in waiters.append(continuation) }
    }

    func release() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statusMessage = "拖入图片或视频即可压缩"
    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var monitoredFolders: [MonitoredFolder] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var canUndoClipboardCompression = false
    @Published private(set) var isDropZoneVisible = true
    @Published private(set) var dropRequestCount = 0
    @Published private(set) var paywallRequest: PaywallRequest?

    let settings = RulesSettings()
    let purchaseManager = PurchaseManager()

    var showDropZoneHandler: (() -> Void)?
    var hideDropZoneHandler: (() -> Void)?
    var dropAcceptedHandler: (() -> Void)?
    var showPaywallHandler: (() -> Void)?

    private enum FileSource: Equatable {
        case automatic
        case manualDrop
    }

    private enum UndoAction {
        case image(data: Data, typeIdentifier: String, changeCount: Int)
        case files(urls: [URL], changeCount: Int)

        var changeCount: Int {
            switch self {
            case .image(_, _, let value), .files(_, let value): return value
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let clipboardMonitor = ClipboardMonitor()
    private let fileProcessingGate = FileProcessingGate()
    private let usageTracker = UsageTracker()
    private var folderBookmarks: [FolderBookmark] = []
    private var directoryWatchers: [UUID: DirectoryWatcher] = [:]
    private var scopedFolderURLs: [UUID: URL] = [:]
    private var pendingClipboardPayloads: [ClipboardPayload] = []
    private var clipboardTaskRunning = false
    private var undoAction: UndoAction?
    private var processingCount = 0
    private var didStart = false

    private let folderBookmarksKey = "monitoredFolderBookmarks"
    private let legacyBookmarkKey = "watchedFolderBookmark"
    private let historyKey = "compressionHistory"
    private let totalSavedKey = "totalSavedBytes"
    private let dailyCountKey = "dailyCompressionCount"
    private let dailyCountDateKey = "dailyCompressionDate"

    var totalSavedBytes: Int64 { defaults.object(forKey: totalSavedKey) as? Int64 ?? 0 }
    var weeklySavedBytes: Int64 { usageTracker.weeklySavedBytes }
    var automaticImageCountToday: Int { usageTracker.imageCountToday }
    var automaticVideoCountToday: Int { usageTracker.videoCountToday }
    var isWatchingFolder: Bool { !directoryWatchers.isEmpty }
    func isFolderWatching(_ folder: MonitoredFolder) -> Bool { directoryWatchers[folder.id] != nil }
    var watchedFolderPath: String? {
        monitoredFolders.first(where: { directoryWatchers[$0.id] != nil })?.path
    }

    var todayCompressionCount: Int {
        guard let date = defaults.object(forKey: dailyCountDateKey) as? Date,
              Calendar.current.isDateInToday(date) else { return 0 }
        return defaults.integer(forKey: dailyCountKey)
    }

    var latestOutputURL: URL? {
        guard let path = history.first(where: { $0.outputPath != nil })?.outputPath else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    init() {
        if let data = defaults.data(forKey: historyKey),
           let items = try? PropertyListDecoder().decode([HistoryItem].self, from: data) {
            history = items
        }

        if let data = defaults.data(forKey: folderBookmarksKey),
           let records = try? PropertyListDecoder().decode([FolderBookmark].self, from: data) {
            folderBookmarks = records
        } else if let legacyData = defaults.data(forKey: legacyBookmarkKey),
                  let (url, refreshedData) = Self.resolveBookmark(legacyData) {
            folderBookmarks = [FolderBookmark(path: url.path, bookmarkData: refreshedData)]
            defaults.removeObject(forKey: legacyBookmarkKey)
            persistFolderBookmarks()
        }
        monitoredFolders = folderBookmarks.map { MonitoredFolder(id: $0.id, path: $0.path) }

        purchaseManager.onEntitlementChanged = { [weak self] isPro in
            self?.handleEntitlementChange(isPro: isPro)
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        purchaseManager.start()
        Task { [weak self] in
            guard let self else { return }
            await self.purchaseManager.refreshEntitlements()
            self.activateAutomation()
        }
    }

    func stop() {
        clipboardMonitor.stop()
        stopAllFolderWatchers()
        didStart = false
    }

    func setClipboardMonitoringEnabled(_ enabled: Bool) {
        settings.setClipboardMonitoringEnabled(enabled)
        guard didStart else { return }
        if enabled {
            configureClipboardMonitor()
            clipboardMonitor.start()
        } else {
            clipboardMonitor.stop()
            statusMessage = "已暂停剪贴板自动压缩"
        }
    }

    func setFolderMonitoringEnabled(_ enabled: Bool) {
        settings.setFolderMonitoringEnabled(enabled)
        guard didStart else { return }
        if enabled {
            restoreFolderWatchers()
        } else {
            stopAllFolderWatchers()
            statusMessage = "已暂停文件夹自动监控"
        }
    }

    func setProFeature(_ feature: ProFeature, enabled: Bool) {
        guard enabled else {
            settings.set(feature, enabled: false)
            return
        }
        guard purchaseManager.isPro else {
            requestPro(for: .feature(feature))
            return
        }
        if feature == .webPOutput, !ImageCompressor.webPEncodingAvailable {
            statusMessage = "此 macOS 版本暂不支持 WebP 编码"
            return
        }
        settings.set(feature, enabled: true)
    }

    func chooseWatchedFolder() {
        guard purchaseManager.isPro || folderBookmarks.isEmpty else {
            requestPro(for: .secondFolder)
            return
        }

        let panel = NSOpenPanel()
        panel.title = "选择截图和录屏监控文件夹"
        panel.message = "只会处理名称像截图或录屏的图片，以及录屏 MOV。"
        panel.prompt = "添加文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !folderBookmarks.contains(where: { $0.path == url.path }) else {
            statusMessage = "此文件夹已添加"
            return
        }

        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let folder = FolderBookmark(path: url.path, bookmarkData: data)
            folderBookmarks.append(folder)
            persistFolderBookmarks()
            if settings.folderMonitoringEnabled && didStart {
                installFolderWatcher(for: folder, url: url)
            }
            statusMessage = settings.folderMonitoringEnabled
                ? "已添加监控：\(url.lastPathComponent)"
                : "已添加文件夹；开启文件夹监控后生效"
        } catch {
            statusMessage = "无法保存文件夹授权：\(error.localizedDescription)"
        }
    }

    func removeWatchedFolder(_ folder: MonitoredFolder) {
        stopFolderWatcher(id: folder.id)
        folderBookmarks.removeAll { $0.id == folder.id }
        persistFolderBookmarks()
        statusMessage = "已移除文件夹：\(folder.displayName)"
    }

    func stopWatchingFolder() {
        setFolderMonitoringEnabled(false)
    }

    func processDroppedURLs(_ urls: [URL]) {
        let validURLs = urls.filter(\.isFileURL)
        guard !validURLs.isEmpty else { return }
        guard validURLs.count == 1 || purchaseManager.isPro else {
            statusMessage = "批量压缩需要 DropSqueeze Pro"
            requestPro(for: .batchCompression)
            return
        }
        dropRequestCount += 1
        dropAcceptedHandler?()
        for url in validURLs {
            Task { await processFile(url, source: .manualDrop) }
        }
    }

    func requestPro(for reason: PaywallReason) {
        if paywallRequest == nil {
            paywallRequest = PaywallRequest(reason: reason, weeklySavedBytes: usageTracker.weeklySavedBytes)
        }
        showPaywallHandler?()
    }

    func dismissPaywall() {
        paywallRequest = nil
    }

    func clearHistory() {
        history = []
        defaults.removeObject(forKey: historyKey)
        statusMessage = "本地压缩历史已清除"
    }

    func undoClipboardCompression() {
        guard let undoAction else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == undoAction.changeCount else {
            self.undoAction = nil
            canUndoClipboardCompression = false
            statusMessage = "剪贴板内容已变化，无法撤销"
            return
        }

        pasteboard.clearContents()
        let didRestore: Bool
        switch undoAction {
        case .image(let data, let typeIdentifier, _):
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
            item.setData(Data([1]), forType: ClipboardMonitor.processedPasteboardType)
            didRestore = pasteboard.writeObjects([item])
        case .files(let urls, _):
            didRestore = pasteboard.writeObjects(filePasteboardItems(for: urls))
        }
        guard didRestore else {
            self.undoAction = nil
            canUndoClipboardCompression = false
            statusMessage = "无法还原剪贴板"
            return
        }
        self.undoAction = nil
        canUndoClipboardCompression = false
        statusMessage = "已还原剪贴板"
    }

    func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func toggleDropZone() {
        if isDropZoneVisible { hideDropZoneHandler?() } else { showDropZoneHandler?() }
    }

    func setDropZoneVisible(_ isVisible: Bool) {
        isDropZoneVisible = isVisible
    }

    private func activateAutomation() {
        configureClipboardMonitor()
        if settings.clipboardMonitoringEnabled { clipboardMonitor.start() }
        restoreFolderWatchers()
    }

    private func configureClipboardMonitor() {
        clipboardMonitor.onPayload = { [weak self] payload in
            Task { @MainActor in self?.enqueueClipboardPayload(payload) }
        }
        clipboardMonitor.onExternalChange = { [weak self] in
            Task { @MainActor in
                self?.undoAction = nil
                self?.canUndoClipboardCompression = false
            }
        }
    }

    private func filePasteboardItems(for urls: [URL]) -> [NSPasteboardItem] {
        urls.map { url in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            item.setData(Data([1]), forType: ClipboardMonitor.processedPasteboardType)
            return item
        }
    }

    private func enqueueClipboardPayload(_ payload: ClipboardPayload) {
        guard settings.clipboardMonitoringEnabled else { return }
        undoAction = nil
        canUndoClipboardCompression = false
        pendingClipboardPayloads.append(payload)
        runNextClipboardPayloadIfNeeded()
    }

    private func runNextClipboardPayloadIfNeeded() {
        guard !clipboardTaskRunning, !pendingClipboardPayloads.isEmpty else { return }
        clipboardTaskRunning = true
        isProcessing = true
        let payload = pendingClipboardPayloads.removeFirst()
        Task { await processClipboardPayload(payload) }
    }

    private func processClipboardPayload(_ payload: ClipboardPayload) async {
        switch payload {
        case .image(let data, let typeIdentifier, let changeCount):
            await processClipboardImage(data: data, typeIdentifier: typeIdentifier, changeCount: changeCount)
        case .files(let urls, let changeCount):
            await processClipboardFiles(urls: urls, changeCount: changeCount)
        }
    }

    private func processClipboardImage(data: Data, typeIdentifier: String, changeCount: Int) async {
        guard let reservation = usageTracker.reserve(.image, isPro: purchaseManager.isPro) else {
            statusMessage = "今日免费图片额度已用完"
            requestPro(for: .imageQuota)
            finishClipboardTask()
            return
        }
        var succeeded = false
        defer { usageTracker.complete(reservation, succeeded: succeeded) }

        do {
            let options = settings.imageOptions
            guard !options.outputWebP || ImageCompressor.webPEncodingAvailable else {
                throw ImageCompressionError.webPUnavailable
            }
            guard let result = try await Task.detached(priority: .utility, operation: {
                try ImageCompressor.compress(data: data, typeIdentifier: typeIdentifier, options: options)
            }).value else {
                statusMessage = "剪贴板图片已是当前编码下的最小结果"
                finishClipboardTask()
                return
            }
            guard NSPasteboard.general.changeCount == changeCount else {
                statusMessage = "剪贴板已变化，跳过旧图片"
                finishClipboardTask()
                return
            }
            let item = NSPasteboardItem()
            item.setData(result.data, forType: NSPasteboard.PasteboardType(result.typeIdentifier))
            item.setData(Data([1]), forType: ClipboardMonitor.processedPasteboardType)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else {
                let original = NSPasteboardItem()
                original.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
                original.setData(Data([1]), forType: ClipboardMonitor.processedPasteboardType)
                pasteboard.clearContents()
                _ = pasteboard.writeObjects([original])
                statusMessage = "无法更新剪贴板，原图片已保留"
                finishClipboardTask()
                return
            }
            undoAction = .image(data: data, typeIdentifier: typeIdentifier, changeCount: pasteboard.changeCount)
            canUndoClipboardCompression = true
            let itemRecord = HistoryItem(
                name: "剪贴板图片",
                kind: .clipboardImage,
                originalBytes: Int64(result.originalByteCount),
                resultBytes: Int64(result.data.count)
            )
            record(itemRecord)
            succeeded = true
            let percent = savingPercent(originalBytes: Int64(result.originalByteCount), resultBytes: Int64(result.data.count))
            statusMessage = "已省 \(percent)% · \(formattedSize(Int64(result.originalByteCount))) → \(formattedSize(Int64(result.data.count)))"
        } catch {
            statusMessage = "剪贴板图片未处理：\(error.localizedDescription)"
        }
        finishClipboardTask()
    }

    private func processClipboardFiles(urls: [URL], changeCount: Int) async {
        var compressedURLs: [URL] = []
        var didCompress = false
        for url in urls {
            if let resultURL = await processFile(url, source: .automatic, reportStatus: false) {
                compressedURLs.append(resultURL)
                didCompress = didCompress || resultURL != url
            } else {
                compressedURLs.append(url)
            }
        }

        let pasteboard = NSPasteboard.general
        if didCompress, pasteboard.changeCount == changeCount {
            pasteboard.clearContents()
            guard pasteboard.writeObjects(filePasteboardItems(for: compressedURLs)) else {
                pasteboard.clearContents()
                _ = pasteboard.writeObjects(filePasteboardItems(for: urls))
                statusMessage = "无法更新剪贴板，原文件仍可用"
                finishClipboardTask()
                return
            }
            undoAction = .files(urls: urls, changeCount: pasteboard.changeCount)
            canUndoClipboardCompression = true
            statusMessage = "已压缩剪贴板中的文件，可直接粘贴压缩副本"
        }
        finishClipboardTask()
    }

    private func finishClipboardTask() {
        clipboardTaskRunning = false
        isProcessing = processingCount > 0
        runNextClipboardPayloadIfNeeded()
    }

    @discardableResult
    private func processFile(_ url: URL, source: FileSource, reportStatus: Bool = true) async -> URL? {
        guard url.isFileURL else { return nil }
        let ext = url.pathExtension.lowercased()
        let isImage = ImageCompressor.typeIdentifier(forFileExtension: ext) != nil
        let isVideo = ext == "mov" || ext == "mp4"
        guard isImage || isVideo else {
            if reportStatus { statusMessage = "暂不支持 \(url.pathExtension.uppercased())" }
            return nil
        }

        await fileProcessingGate.acquire()
        defer { Task { await fileProcessingGate.release() } }

        let reservation: UsageReservation?
        if source == .automatic {
            let kind: AutomaticUsageKind = isImage ? .image : .video
            guard let value = usageTracker.reserve(kind, isPro: purchaseManager.isPro) else {
                let reason: PaywallReason = isImage ? .imageQuota : .videoQuota
                statusMessage = isImage ? "今日免费图片额度已用完" : "今日免费视频额度已用完"
                requestPro(for: reason)
                return nil
            }
            reservation = value
        } else {
            reservation = nil
        }
        var succeeded = false
        defer {
            if let reservation { usageTracker.complete(reservation, succeeded: succeeded) }
        }

        let startedAccess = url.startAccessingSecurityScopedResource()
        defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
        processingCount += 1
        isProcessing = true
        defer {
            processingCount = max(0, processingCount - 1)
            isProcessing = clipboardTaskRunning || processingCount > 0
        }

        do {
            let outputURL: URL
            let originalSize: Int64
            let resultSize: Int64

            if isImage {
                let options = settings.imageOptions
                guard !options.outputWebP || ImageCompressor.webPEncodingAvailable else {
                    throw ImageCompressionError.webPUnavailable
                }
                let output = try await Task.detached(priority: .utility) { () throws -> (URL, CompressedImage)? in
                    guard let compressed = try ImageCompressor.compressFile(at: url, options: options) else { return nil }
                    return (try ImageCompressor.writeCompressedFile(compressed, beside: url), compressed)
                }.value
                guard let (writtenURL, compressed) = output else {
                    if reportStatus { statusMessage = "\(url.lastPathComponent)：没有更小的结果，原件保留" }
                    return nil
                }
                outputURL = writtenURL
                originalSize = Int64(compressed.originalByteCount)
                resultSize = Int64(compressed.data.count)
            } else {
                if ext == "mov", settings.gifConversionEnabled {
                    outputURL = try await GIFGenerator.generateSmallerGIF(from: url)
                } else {
                    outputURL = try await VideoTranscoder.transcodeToSmallerMP4(url)
                }
                originalSize = Self.fileSize(at: url)
                resultSize = Self.fileSize(at: outputURL)
            }

            record(HistoryItem(
                name: url.lastPathComponent,
                kind: isImage ? .imageFile : .videoFile,
                originalBytes: originalSize,
                resultBytes: resultSize,
                outputPath: outputURL.path
            ))
            succeeded = true
            if reportStatus {
                let percent = savingPercent(originalBytes: originalSize, resultBytes: resultSize)
                statusMessage = "\(isImage ? "图片" : "视频")已省 \(percent)%：\(outputURL.lastPathComponent)"
            }
            return outputURL
        } catch {
            if reportStatus { statusMessage = "\(url.lastPathComponent)：\(error.localizedDescription)" }
            return nil
        }
    }

    private func record(_ item: HistoryItem) {
        history.insert(item, at: 0)
        history = Array(history.prefix(10))
        defaults.set(try? PropertyListEncoder().encode(history), forKey: historyKey)
        defaults.set(totalSavedBytes + item.savedBytes, forKey: totalSavedKey)
        usageTracker.recordSavedBytes(item.savedBytes)
        if let date = defaults.object(forKey: dailyCountDateKey) as? Date,
           Calendar.current.isDateInToday(date) {
            defaults.set(defaults.integer(forKey: dailyCountKey) + 1, forKey: dailyCountKey)
        } else {
            defaults.set(Date(), forKey: dailyCountDateKey)
            defaults.set(1, forKey: dailyCountKey)
        }
    }

    private func savingPercent(originalBytes: Int64, resultBytes: Int64) -> Int {
        guard originalBytes > 0, resultBytes < originalBytes else { return 0 }
        return Int((Double(originalBytes - resultBytes) / Double(originalBytes)) * 100)
    }

    private func restoreFolderWatchers() {
        stopAllFolderWatchers()
        guard settings.folderMonitoringEnabled else { return }
        var didRefreshBookmarks = false
        for folder in folderBookmarks {
            if !purchaseManager.isPro, !directoryWatchers.isEmpty { break }
            guard let (url, refreshedData) = Self.resolveBookmark(folder.bookmarkData) else {
                statusMessage = "監控文件夹授权已失效：\(folder.path)"
                continue
            }
            if refreshedData != folder.bookmarkData,
               let index = folderBookmarks.firstIndex(where: { $0.id == folder.id }) {
                folderBookmarks[index].bookmarkData = refreshedData
                didRefreshBookmarks = true
            }
            installFolderWatcher(for: folder, url: url)
        }
        if didRefreshBookmarks { persistFolderBookmarks() }
        if isWatchingFolder, !purchaseManager.isPro, folderBookmarks.count > 1 {
            statusMessage = "免费版正在监控第一个文件夹；升级 Pro 可同时监控多个"
        }
    }

    private func installFolderWatcher(for folder: FolderBookmark, url: URL) {
        guard directoryWatchers[folder.id] == nil else { return }
        let startedAccess = url.startAccessingSecurityScopedResource()
        guard startedAccess else {
            statusMessage = "无法持续访问此文件夹，请重新选择：\(url.lastPathComponent)"
            return
        }

        let watcher = DirectoryWatcher(directoryURL: url) { [weak self] urls in
            guard let self else { return }
            for candidate in urls {
                Task { await self.processFile(candidate, source: .automatic) }
            }
        }
        guard watcher.start() else {
            url.stopAccessingSecurityScopedResource()
            statusMessage = "无法监控此文件夹，请重新授权：\(url.lastPathComponent)"
            return
        }
        directoryWatchers[folder.id] = watcher
        scopedFolderURLs[folder.id] = url
        statusMessage = "正在监控：\(url.lastPathComponent)"
    }

    private func stopFolderWatcher(id: UUID) {
        directoryWatchers.removeValue(forKey: id)?.stop()
        scopedFolderURLs.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
    }

    private func stopAllFolderWatchers() {
        for id in Array(directoryWatchers.keys) { stopFolderWatcher(id: id) }
    }

    private func persistFolderBookmarks() {
        if let data = try? PropertyListEncoder().encode(folderBookmarks) {
            defaults.set(data, forKey: folderBookmarksKey)
        }
        monitoredFolders = folderBookmarks.map { MonitoredFolder(id: $0.id, path: $0.path) }
    }

    private func handleEntitlementChange(isPro: Bool) {
        if isPro {
            statusMessage = "DropSqueeze Pro 已解锁"
        } else {
            settings.disableProFeatures()
            statusMessage = "Pro 权限已结束，高阶规则已关闭"
        }
        if didStart { restoreFolderWatchers() }
    }

    private static func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func resolveBookmark(_ data: Data) -> (URL, Data)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard isStale else { return (url, data) }

        let startedAccess = url.startAccessingSecurityScopedResource()
        defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
        guard let refreshedData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }
        return (url, refreshedData)
    }
}
