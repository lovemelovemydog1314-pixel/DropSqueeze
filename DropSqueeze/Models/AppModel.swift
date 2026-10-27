import AppKit
import AVFoundation
import Combine
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct MediaTechnicalDetails: Codable, Equatable {
    let format: String
    let width: Int?
    let height: Int?
    let framesPerSecond: Double?
    let videoCodec: String?
    let audioTrackCount: Int?
    let pageCount: Int?

    var summary: String {
        var values = [format]
        if let width, let height { values.append("\(width) × \(height)") }
        if let videoCodec { values.append(videoCodec) }
        if let framesPerSecond {
            let roundedFrameRate = framesPerSecond.rounded()
            values.append("\(Int(roundedFrameRate)) fps")
        }
        if let audioTrackCount { values.append(audioTrackCount == 0 ? "无音轨" : "含音轨") }
        if let pageCount { values.append("\(pageCount) 页") }
        return values.joined(separator: " · ")
    }

    static func read(from url: URL, kind: HistoryItem.Kind) async -> MediaTechnicalDetails? {
        switch kind {
        case .imageFile:
            return imageDetails(at: url)
        case .videoFile:
            return await videoDetails(at: url)
        case .pdfFile:
            return pdfDetails(at: url)
        case .clipboardImage:
            return nil
        }
    }

    private static func imageDetails(at url: URL) -> MediaTechnicalDetails? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let typeIdentifier = CGImageSourceGetType(source) as String?
        let format = typeIdentifier.flatMap { UTType($0)?.preferredFilenameExtension?.uppercased() }
            ?? url.pathExtension.uppercased()
        return MediaTechnicalDetails(
            format: format.isEmpty ? "图片" : format,
            width: properties[kCGImagePropertyPixelWidth] as? Int,
            height: properties[kCGImagePropertyPixelHeight] as? Int,
            framesPerSecond: nil,
            videoCodec: nil,
            audioTrackCount: nil,
            pageCount: nil
        )
    }

    private static func videoDetails(at url: URL) async -> MediaTechnicalDetails? {
        let asset = AVURLAsset(url: url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let orientedBounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let width = Int(abs(orientedBounds.width).rounded())
            let height = Int(abs(orientedBounds.height).rounded())
            let frameRate = Double(try await track.load(.nominalFrameRate))
            let descriptions = try await track.load(.formatDescriptions)
            let codec = descriptions.first.map { videoCodecName(CMFormatDescriptionGetMediaSubType($0)) }
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            return MediaTechnicalDetails(
                format: url.pathExtension.uppercased().isEmpty ? "视频" : url.pathExtension.uppercased(),
                width: width > 0 ? width : nil,
                height: height > 0 ? height : nil,
                framesPerSecond: frameRate.isFinite && frameRate > 0 ? frameRate : nil,
                videoCodec: codec,
                audioTrackCount: audioTracks.count,
                pageCount: nil
            )
        } catch {
            return nil
        }
    }

    private static func pdfDetails(at url: URL) -> MediaTechnicalDetails? {
        guard let document = PDFDocument(url: url) else { return nil }
        return MediaTechnicalDetails(
            format: "PDF",
            width: nil,
            height: nil,
            framesPerSecond: nil,
            videoCodec: nil,
            audioTrackCount: nil,
            pageCount: document.pageCount
        )
    }

    private static func videoCodecName(_ subtype: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((subtype >> 24) & 0xff),
            UInt8((subtype >> 16) & 0xff),
            UInt8((subtype >> 8) & 0xff),
            UInt8(subtype & 0xff)
        ]
        let code = String(bytes: bytes, encoding: .ascii)?.lowercased() ?? ""
        switch code {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "apch", "apcn", "apcs", "apco": return "ProRes"
        default: return code.uppercased().isEmpty ? "视频编码" : code.uppercased()
        }
    }
}

struct HistoryItem: Codable, Identifiable {
    enum Kind: String, Codable {
        case clipboardImage
        case imageFile
        case videoFile
        case pdfFile
    }

    let id: UUID
    let name: String
    let kind: Kind
    let originalBytes: Int64
    let resultBytes: Int64
    let date: Date
    let sourcePath: String?
    let outputPath: String?
    let sourceBookmarkData: Data?
    let outputBookmarkData: Data?
    let sourceDetails: MediaTechnicalDetails?
    let outputDetails: MediaTechnicalDetails?

    var savedBytes: Int64 { max(0, originalBytes - resultBytes) }

    init(
        name: String,
        kind: Kind,
        originalBytes: Int64,
        resultBytes: Int64,
        outputPath: String? = nil,
        sourceURL: URL? = nil,
        outputURL: URL? = nil,
        sourceDetails: MediaTechnicalDetails? = nil,
        outputDetails: MediaTechnicalDetails? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.originalBytes = originalBytes
        self.resultBytes = resultBytes
        self.date = Date()
        self.sourcePath = sourceURL?.path
        self.outputPath = outputURL?.path ?? outputPath
        self.sourceBookmarkData = Self.makeBookmark(for: sourceURL)
        self.outputBookmarkData = Self.makeBookmark(for: outputURL)
        self.sourceDetails = sourceDetails
        self.outputDetails = outputDetails
    }

    var resolvedSourceURL: URL? {
        Self.resolveBookmark(sourceBookmarkData) ?? sourcePath.map { URL(fileURLWithPath: $0) }
    }

    var resolvedOutputURL: URL? {
        Self.resolveBookmark(outputBookmarkData) ?? outputPath.map { URL(fileURLWithPath: $0) }
    }

    private static func makeBookmark(for url: URL?) -> Data? {
        guard let url else { return nil }
        return try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolveBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}

private struct FileCompressionOutcome {
    let outputURL: URL
    let originalBytes: Int64
    let resultBytes: Int64
    let didConvertFormat: Bool
}

private struct ManualQueueItem {
    let id: UUID
    let batchID: UUID
    let url: URL
    let securityScopeURL: URL
    var profileOverride: SavedCompressionProfile? = nil
}

struct DroppedMediaFile {
    let url: URL
    let securityScopeURL: URL
}

enum BatchMediaFileScanner {
    static let defaultMaximumFiles = 2_000

    static func expand(_ urls: [URL], maximumFiles: Int = defaultMaximumFiles) -> [DroppedMediaFile] {
        guard maximumFiles > 0 else { return [] }
        var results: [DroppedMediaFile] = []
        var seenPaths = Set<String>()

        for url in urls where url.isFileURL {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let startedAccess = url.startAccessingSecurityScopedResource()
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let fileURL as URL in enumerator {
                        if results.count >= maximumFiles { break }
                        guard isSupported(fileURL),
                              seenPaths.insert(fileURL.standardizedFileURL.path).inserted else { continue }
                        results.append(DroppedMediaFile(url: fileURL, securityScopeURL: url))
                    }
                }
                if startedAccess { url.stopAccessingSecurityScopedResource() }
            } else if isSupported(url), seenPaths.insert(url.standardizedFileURL.path).inserted {
                results.append(DroppedMediaFile(url: url, securityScopeURL: url))
            }
            if results.count >= maximumFiles { break }
        }
        return results
    }

    static func isSupported(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        let extensionName = url.pathExtension.lowercased()
        return extensionName == "svg"
            || ImageCompressor.typeIdentifier(forFileExtension: extensionName) != nil
            || ImageCompressor.detectedTypeIdentifier(at: url) != nil
            || ["mov", "mp4", "m4v", "pdf"].contains(extensionName)
    }
}

struct QueueProfileChoice: Equatable {
    let identifier: String
    let profile: SavedCompressionProfile?

    var title: String { profile?.name ?? "当前设置" }

    static func resolve(_ identifier: String, savedProfiles: [SavedCompressionProfile]) -> QueueProfileChoice? {
        if CompressionProfileReference.isCurrent(identifier) {
            return QueueProfileChoice(identifier: identifier, profile: nil)
        }
        guard let profile = CompressionProfileReference.resolve(identifier, savedProfiles: savedProfiles) else {
            return nil
        }
        return QueueProfileChoice(identifier: identifier, profile: profile)
    }
}

enum CompressionQueueState: String, Identifiable {
    case queued
    case processing
    case completed
    case skipped
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queued: return "排队中"
        case .processing: return "处理中"
        case .completed: return "完成"
        case .skipped: return "跳过"
        case .cancelled: return "已取消"
        }
    }
}

struct CompressionQueueJob: Identifiable {
    let id: UUID
    let url: URL
    let securityScopeURL: URL
    var state: CompressionQueueState
    var progress: Double?
    var detail: String?
    var startedAt: Date?
    var finishedAt: Date?
    var profileIdentifier = CompressionProfileReference.currentIdentifier
    var profileOverride: SavedCompressionProfile?
}

private struct ManualQueueBatch {
    var remainingCount: Int
    var outcomes: [FileCompressionOutcome] = []
}

enum ShortcutCompressionError: LocalizedError {
    case batchRequiresPro
    case pdfRequiresPro
    case selectedProfileUnavailable
    case selectedFeatureRequiresPro
    case invalidMaximumSize
    case noSupportedFiles

    var errorDescription: String? {
        switch self {
        case .batchRequiresPro: return "快捷指令批量压缩需要 DropSqueeze Pro。"
        case .pdfRequiresPro: return "PDF 压缩需要 DropSqueeze Pro。"
        case .selectedProfileUnavailable: return "所选压缩配置已删除，请在快捷指令中重新选择。"
        case .selectedFeatureRequiresPro: return "此压缩配置包含 Pro 功能，请升级后继续。"
        case .invalidMaximumSize: return "图片体积上限需为 0.1–5000 MB，视频上限需为 1–5000 MB。"
        case .noSupportedFiles: return "没有生成压缩副本；请检查文件格式或选择更大的输出预设。"
        }
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
    static weak var shared: AppModel?

    @Published private(set) var statusMessage = "拖入图片或视频即可压缩"
    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var monitoredFolders: [MonitoredFolder] = []
    @Published private(set) var outputFolderURL: URL?
    @Published private(set) var requiresOutputFolderAuthorization = false
    @Published private(set) var currentFileName: String?
    @Published private(set) var currentProgress: Double?
    @Published private(set) var queuedFileCount = 0
    @Published private(set) var isManualQueueRunning = false
    @Published private(set) var isManualQueuePaused = false
    @Published private(set) var queueJobs: [CompressionQueueJob] = []
    @Published private(set) var estimatedQueueRemainingSeconds: TimeInterval?
    @Published private(set) var isProcessing = false
    @Published private(set) var canUndoClipboardCompression = false
    @Published private(set) var clipboardCollectionItems: [ClipboardCollectionItem] = []
    @Published private(set) var isDropZoneVisible = true
    @Published private(set) var dropRequestCount = 0
    @Published private(set) var paywallRequest: PaywallRequest?
    @Published var latestRecognizedText: String?

    let settings = RulesSettings()
    let purchaseManager = PurchaseManager()

    var showDropZoneHandler: (() -> Void)?
    var hideDropZoneHandler: (() -> Void)?
    var dropAcceptedHandler: (() -> Void)?
    var showPaywallHandler: (() -> Void)?
    var showFloatingPillHandler: (() -> Void)?
    var compressionNotificationHandler: ((CompressionNotice) -> Void)?

    private enum FileSource: Equatable {
        case automatic
        case manualDrop
        case shortcut
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
    private var clipboardCollection = ClipboardCollectionBuffer()
    private let fileProcessingGate = FileProcessingGate()
    private let usageTracker = UsageTracker()
    private var folderBookmarks: [FolderBookmark] = []
    private var directoryWatchers: [UUID: DirectoryWatcher] = [:]
    private var scopedFolderURLs: [UUID: URL] = [:]
    private var pendingClipboardPayloads: [ClipboardPayload] = []
    private var manualFileQueue: [ManualQueueItem] = []
    private var manualQueueBatches: [UUID: ManualQueueBatch] = [:]
    private var completedQueueDurations: [TimeInterval] = []
    private var processingFilePaths: Set<String> = []
    private var generatedOutputPaths: [String: Date] = [:]
    private var activeVideoCancellation: VideoTranscoderCancellation?
    private var activeFileSource: FileSource?
    private var activeProgressID: UUID?
    private var clipboardTaskRunning = false
    private var undoAction: UndoAction?
    private var undoActionID: UUID?
    private var processingCount = 0
    private var didStart = false

    private let folderBookmarksKey = "monitoredFolderBookmarks"
    private let legacyBookmarkKey = "watchedFolderBookmark"
    private let outputFolderBookmarkKey = "outputFolderBookmark"
    private let historyKey = "compressionHistory"
    private let totalSavedKey = "totalSavedBytes"
    private let totalCountKey = "totalCompressionCount"
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

    var totalCompressionCount: Int {
        defaults.integer(forKey: totalCountKey)
    }

    var todayCompressionCount: Int {
        guard let date = defaults.object(forKey: dailyCountDateKey) as? Date,
              Calendar.current.isDateInToday(date) else { return 0 }
        return defaults.integer(forKey: dailyCountKey)
    }

    var latestOutputURL: URL? {
        history.lazy.compactMap { item -> URL? in
            guard let url = item.resolvedOutputURL else { return nil }
            let startedAccess = url.startAccessingSecurityScopedResource()
            defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }.first
    }

    init() {
        Self.shared = self
        if let data = defaults.data(forKey: historyKey),
           let items = try? PropertyListDecoder().decode([HistoryItem].self, from: data) {
            history = items
        }

        if let data = defaults.data(forKey: outputFolderBookmarkKey) {
            if let (url, refreshedData) = Self.resolveBookmark(data) {
                outputFolderURL = url
                if refreshedData != data { defaults.set(refreshedData, forKey: outputFolderBookmarkKey) }
            } else {
                requiresOutputFolderAuthorization = true
            }
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
        monitoredFolders = folderBookmarks.map { MonitoredFolder(id: $0.id, path: $0.path, rule: $0.rule) }

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
        updateClipboardMonitorState()
        statusMessage = enabled ? "已开启剪贴板自动压缩" : "已暂停剪贴板自动压缩"
    }

    func setClipboardCollectionEnabled(_ enabled: Bool) {
        settings.setClipboardCollectionEnabled(enabled)
        updateClipboardMonitorState()
        if enabled, let currentPayload = ClipboardMonitor.currentPayload() {
            collectClipboardPayload(currentPayload)
        }
        statusMessage = enabled ? "剪贴板收集栏已开启；内容仅保留到退出应用" : "剪贴板收集已关闭"
    }

    func copyClipboardCollectionItem(_ item: ClipboardCollectionItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects(item.pasteboardItems()) else {
            statusMessage = "无法将内容放回剪贴板"
            return
        }
        statusMessage = "已放回剪贴板：\(item.displayName)"
    }

    func removeClipboardCollectionItem(_ item: ClipboardCollectionItem) {
        clipboardCollection.remove(id: item.id)
        clipboardCollectionItems = clipboardCollection.items
    }

    func clearClipboardCollection() {
        clipboardCollection.clear()
        clipboardCollectionItems = []
        statusMessage = "剪贴板收集栏已清空"
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

    func setVideoOutputPreset(_ preset: VideoOutputPreset) {
        settings.setVideoOutputPreset(preset)
        statusMessage = "视频输出预设已设为：\(preset.title)"
    }

    func applyCompressionScenario(_ scenario: CompressionScenario) {
        if let feature = scenario.requiredProFeature, !purchaseManager.isPro {
            requestPro(for: .feature(feature))
            return
        }
        if let typeIdentifier = scenario.profile.imageFileOutputFormat.typeIdentifier,
           !ImageCompressor.encodingAvailable(for: typeIdentifier) {
            statusMessage = "当前 macOS 无法应用此预设的图片格式"
            return
        }
        settings.applyScenario(scenario)
        statusMessage = "已应用预设：\(scenario.title)"
    }

    func applySavedProfile(_ profile: SavedCompressionProfile) {
        if let feature = profile.requiredProFeature, !purchaseManager.isPro {
            requestPro(for: .feature(feature))
            return
        }
        if let type = profile.imageFileOutputFormat.typeIdentifier, !ImageCompressor.encodingAvailable(for: type) {
            statusMessage = "当前 macOS 无法编码为此预设的图片格式"
            return
        }
        settings.apply(profile)
        statusMessage = "已应用配置：\(profile.name)"
    }

    func setImageFileOutputFormat(_ format: ImageFileOutputFormat) {
        if let typeIdentifier = format.typeIdentifier,
           !ImageCompressor.encodingAvailable(for: typeIdentifier) {
            statusMessage = "当前 macOS 无法编码为所选图片格式"
            return
        }
        if format == .webP {
            guard purchaseManager.isPro else {
                requestPro(for: .feature(.fileWebPOutput))
                return
            }
        }
        settings.setImageFileOutputFormat(format)
        statusMessage = "文件图片输出格式已设为：\(format.title)"
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        settings.setNotificationsEnabled(enabled)
        statusMessage = enabled ? "压缩完成通知已开启" : "压缩完成通知已关闭"
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
        if (feature == .clipboardWebPOutput || feature == .fileWebPOutput),
           !ImageCompressor.webPEncodingAvailable {
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

    func chooseOutputFolder() {
        let currentFolder = outputFolderURL
        let startedCurrentFolderAccess = currentFolder?.startAccessingSecurityScopedResource() ?? false
        defer { if startedCurrentFolderAccess { currentFolder?.stopAccessingSecurityScopedResource() } }

        let panel = NSOpenPanel()
        panel.title = "选择压缩结果保存位置"
        panel.message = "所有文件压缩结果会保存到此文件夹；原文件保持不变。"
        panel.prompt = "使用此文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentFolder
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            outputFolderURL = url
            requiresOutputFolderAuthorization = false
            defaults.set(data, forKey: outputFolderBookmarkKey)
            statusMessage = "压缩结果将保存到：\(url.lastPathComponent)"
        } catch {
            statusMessage = "无法保存输出文件夹授权：\(error.localizedDescription)"
        }
    }

    func resetOutputFolder() {
        outputFolderURL = nil
        requiresOutputFolderAuthorization = false
        defaults.removeObject(forKey: outputFolderBookmarkKey)
        statusMessage = "压缩结果将保存到各原文件所在文件夹"
    }

    func removeWatchedFolder(_ folder: MonitoredFolder) {
        stopFolderWatcher(id: folder.id)
        folderBookmarks.removeAll { $0.id == folder.id }
        persistFolderBookmarks()
        statusMessage = "已移除文件夹：\(folder.displayName)"
    }

    func updateFolderRule(_ id: UUID, rule: FolderWatchRule) {
        guard let index = folderBookmarks.firstIndex(where: { $0.id == id }), folderBookmarks[index].rule != rule else { return }
        folderBookmarks[index].rule = rule
        persistFolderBookmarks()
        if let url = scopedFolderURLs[id] {
            stopFolderWatcher(id: id)
            installFolderWatcher(for: folderBookmarks[index], url: url)
        }
        statusMessage = "监控规则已更新"
    }

    func stopWatchingFolder() {
        setFolderMonitoringEnabled(false)
    }

    func processDroppedURLs(_ urls: [URL]) {
        let validURLs = expandDroppedFiles(urls)
        guard !validURLs.isEmpty else { return }
        guard validURLs.count == 1 || purchaseManager.isPro else {
            statusMessage = "批量压缩需要 DropSqueeze Pro"
            requestPro(for: .batchCompression)
            return
        }
        dropRequestCount += 1
        dropAcceptedHandler?()
        let batchID = UUID()
        manualQueueBatches[batchID] = ManualQueueBatch(remainingCount: validURLs.count)
        let queueItems = validURLs.map { file in
            let id = UUID()
            queueJobs.append(CompressionQueueJob(
                id: id,
                url: file.url,
                securityScopeURL: file.securityScopeURL,
                state: .queued
            ))
            return ManualQueueItem(id: id, batchID: batchID, url: file.url, securityScopeURL: file.securityScopeURL)
        }
        manualFileQueue.append(contentsOf: queueItems)
        trimQueueHistory()
        queuedFileCount = manualFileQueue.count
        guard !isManualQueueRunning else { return }
        isManualQueuePaused = false
        isManualQueueRunning = true
        Task { await drainManualQueue() }
    }

    func pauseManualQueue() {
        guard isManualQueueRunning else { return }
        isManualQueuePaused = true
        statusMessage = "队列已暂停"
    }

    func resumeManualQueue() {
        guard isManualQueueRunning else { return }
        isManualQueuePaused = false
        statusMessage = "继续处理队列"
    }

    func removeQueuedJob(_ id: UUID) {
        guard let index = manualFileQueue.firstIndex(where: { $0.id == id }) else { return }
        let item = manualFileQueue.remove(at: index)
        updateQueueJob(id) {
            $0.state = .cancelled
            $0.finishedAt = Date()
            $0.detail = "已从队列移除"
        }
        queuedFileCount = manualFileQueue.count
        completeManualQueueItem(item, outcome: nil)
        updateQueueEstimate()
    }

    func setQueueJobProfile(_ id: UUID, identifier: String) {
        guard let job = queueJobs.first(where: { $0.id == id }), job.state == .queued else { return }
        guard let selection = QueueProfileChoice.resolve(identifier, savedProfiles: settings.savedProfiles) else { return }

        updateQueueJob(id) {
            $0.profileIdentifier = selection.identifier
            $0.profileOverride = selection.profile
        }
        if let index = manualFileQueue.firstIndex(where: { $0.id == id }) {
            manualFileQueue[index].profileOverride = selection.profile
        }
    }

    func retryQueueJob(_ id: UUID) {
        guard let job = queueJobs.first(where: { $0.id == id }),
              job.state == .skipped || job.state == .cancelled,
              !manualFileQueue.contains(where: { $0.id == id }) else { return }
        let batchID = UUID()
        manualQueueBatches[batchID] = ManualQueueBatch(remainingCount: 1)
        manualFileQueue.append(ManualQueueItem(
            id: job.id,
            batchID: batchID,
            url: job.url,
            securityScopeURL: job.securityScopeURL,
            profileOverride: job.profileOverride
        ))
        updateQueueJob(id) {
            $0.state = .queued
            $0.progress = nil
            $0.detail = "等待重试"
            $0.startedAt = nil
            $0.finishedAt = nil
        }
        queuedFileCount = manualFileQueue.count
        if !isManualQueueRunning {
            isManualQueuePaused = false
            isManualQueueRunning = true
            Task { await drainManualQueue() }
        }
        updateQueueEstimate()
    }

    func stopManualQueue() {
        guard isManualQueueRunning else { return }
        isManualQueuePaused = false
        let pendingItems = manualFileQueue
        manualFileQueue.removeAll()
        queuedFileCount = 0
        for item in pendingItems {
            updateQueueJob(item.id) {
                $0.state = .cancelled
                $0.finishedAt = Date()
                $0.detail = "剩余任务已停止"
            }
            completeManualQueueItem(item, outcome: nil)
        }
        isManualQueuePaused = false
        if activeFileSource == .manualDrop { activeVideoCancellation?.cancel() }
        statusMessage = "已停止剩余压缩任务"
        updateQueueEstimate()
    }

    private func drainManualQueue() async {
        while true {
            guard !manualFileQueue.isEmpty else { break }
            while isManualQueuePaused && !manualFileQueue.isEmpty {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard !manualFileQueue.isEmpty else { break }
            let item = manualFileQueue.removeFirst()
            queuedFileCount = manualFileQueue.count
            updateQueueJob(item.id) {
                $0.state = .processing
                $0.startedAt = Date()
                $0.progress = nil
                $0.detail = nil
            }
            updateQueueEstimate()
            let startedAt = Date()
            statusMessage = "正在压缩：\(item.url.lastPathComponent)"
            let outcome = await processFile(
                item.url,
                source: .manualDrop,
                notifyOnSuccess: false,
                securityScopeURL: item.securityScopeURL,
                profileOverride: item.profileOverride,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in self?.updateQueueProgress(item.id, progress: progress) }
                }
            )
            let cancelled = statusMessage.hasPrefix("已取消：")
            updateQueueJob(item.id) {
                $0.state = outcome != nil ? .completed : (cancelled ? .cancelled : .skipped)
                $0.finishedAt = Date()
                $0.progress = outcome == nil ? nil : 1
                $0.detail = outcome.map { "节省 \(formattedSize($0.originalBytes - $0.resultBytes))" }
                    ?? (cancelled ? "已取消" : statusMessage)
            }
            completedQueueDurations.append(Date().timeIntervalSince(startedAt))
            completedQueueDurations = Array(completedQueueDurations.suffix(20))
            completeManualQueueItem(item, outcome: outcome)
            trimQueueHistory()
            updateQueueEstimate()
        }
        isManualQueueRunning = false
        isManualQueuePaused = false
        estimatedQueueRemainingSeconds = nil
        if currentFileName == nil { currentProgress = nil }
    }

    private func expandDroppedFiles(_ urls: [URL]) -> [DroppedMediaFile] {
        let results = BatchMediaFileScanner.expand(urls)
        if results.count == BatchMediaFileScanner.defaultMaximumFiles {
            statusMessage = "已加入前 \(BatchMediaFileScanner.defaultMaximumFiles) 个支持的文件；超出部分未加入队列"
        } else if results.isEmpty {
            statusMessage = "没有找到支持的图片、视频或 PDF 文件"
        }
        return results
    }

    private func updateQueueJob(_ id: UUID, update: (inout CompressionQueueJob) -> Void) {
        guard let index = queueJobs.firstIndex(where: { $0.id == id }) else { return }
        update(&queueJobs[index])
    }

    private func updateQueueProgress(_ id: UUID, progress: Double) {
        updateQueueJob(id) { $0.progress = min(1, max(0, progress)) }
        updateQueueEstimate()
    }

    private func updateQueueEstimate() {
        guard isManualQueueRunning else {
            estimatedQueueRemainingSeconds = nil
            return
        }
        let averageDuration = completedQueueDurations.isEmpty
            ? 45.0
            : completedQueueDurations.reduce(0, +) / Double(completedQueueDurations.count)
        let active = queueJobs.first(where: { $0.state == .processing })
        let activeRemaining: TimeInterval
        if let active, let startedAt = active.startedAt, let progress = active.progress, progress > 0.02 {
            activeRemaining = max(0, Date().timeIntervalSince(startedAt) * (1 - progress) / progress)
        } else if active != nil {
            activeRemaining = averageDuration
        } else {
            activeRemaining = 0
        }
        estimatedQueueRemainingSeconds = activeRemaining + averageDuration * Double(queuedFileCount)
    }

    private func trimQueueHistory() {
        guard queueJobs.count > 80 else { return }
        let pendingIDs = Set(manualFileQueue.map(\.id))
        let active = queueJobs.filter { $0.state == .processing || pendingIDs.contains($0.id) }
        let completed = queueJobs.filter { $0.state != .processing && !pendingIDs.contains($0.id) }
        queueJobs = Array(completed.suffix(40)) + active
    }

    private func completeManualQueueItem(_ item: ManualQueueItem, outcome: FileCompressionOutcome?) {
        guard var batch = manualQueueBatches[item.batchID] else { return }
        if let outcome { batch.outcomes.append(outcome) }
        batch.remainingCount = max(0, batch.remainingCount - 1)
        if batch.remainingCount == 0 {
            notifyFileCompression(batch.outcomes)
            manualQueueBatches.removeValue(forKey: item.batchID)
        } else {
            manualQueueBatches[item.batchID] = batch
        }
    }

    func compressShortcutFiles(
        _ urls: [URL],
        profileIdentifier: String = CompressionProfileReference.currentIdentifier,
        videoPresetOverride: VideoOutputPreset? = nil,
        maximumVideoSizeMB: Int? = nil,
        maximumImageSizeMB: Double? = nil,
        outputDestination: CompressionOutputDestination = .appDefault
    ) async throws -> [URL] {
        var seenPaths = Set<String>()
        let validURLs = urls.filter { url in
            url.isFileURL && seenPaths.insert(url.standardizedFileURL.path).inserted
        }
        guard !validURLs.isEmpty else { throw ShortcutCompressionError.noSupportedFiles }
        guard maximumVideoSizeMB.map({ (1...5_000).contains($0) }) ?? true else {
            throw ShortcutCompressionError.invalidMaximumSize
        }
        guard maximumImageSizeMB.map({ ImageOutputSizeLimit.bytes(for: $0) != nil }) ?? true else {
            throw ShortcutCompressionError.invalidMaximumSize
        }
        let selectedProfile = CompressionProfileReference.isCurrent(profileIdentifier)
            ? nil
            : CompressionProfileReference.resolve(profileIdentifier, savedProfiles: settings.savedProfiles)
        guard CompressionProfileReference.isCurrent(profileIdentifier) || selectedProfile != nil else {
            throw ShortcutCompressionError.selectedProfileUnavailable
        }
        await purchaseManager.refreshEntitlements()
        guard validURLs.count == 1 || purchaseManager.isPro else {
            requestPro(for: .batchCompression)
            throw ShortcutCompressionError.batchRequiresPro
        }
        guard !validURLs.contains(where: { $0.pathExtension.lowercased() == "pdf" }) || purchaseManager.isPro else {
            requestPro(for: .pdfCompression)
            throw ShortcutCompressionError.pdfRequiresPro
        }
        let shortcutContainsImage = validURLs.contains { url in
            SVGCompressor.isSVG(url: url)
                || ImageCompressor.detectedTypeIdentifier(at: url) != nil
                || ImageCompressor.typeIdentifier(forFileExtension: url.pathExtension) != nil
        }
        let shortcutContainsGIFEligibleVideo = validURLs.contains { $0.pathExtension.lowercased() == "mov" }
        let selectedImageFormat = selectedProfile?.imageFileOutputFormat ?? settings.imageFileOutputFormat
        let selectedRetinaDownscale = selectedProfile?.retinaDownscaleEnabled ?? settings.retinaDownscaleEnabled
        let selectedGIFConversion = selectedProfile?.gifConversionEnabled ?? settings.gifConversionEnabled
        let requiredFeature: ProFeature? = shortcutContainsImage && selectedImageFormat == .webP
            ? .fileWebPOutput
            : (shortcutContainsImage && selectedRetinaDownscale
                ? .retinaDownscale
                : (shortcutContainsGIFEligibleVideo && selectedGIFConversion ? .gifConversion : nil))
        if let feature = requiredFeature, !purchaseManager.isPro {
            requestPro(for: .feature(feature))
            throw ShortcutCompressionError.selectedFeatureRequiresPro
        }
        if shortcutContainsImage,
           let typeIdentifier = selectedImageFormat.typeIdentifier,
           !ImageCompressor.encodingAvailable(for: typeIdentifier) {
            throw ShortcutCompressionError.noSupportedFiles
        }

        var outcomes: [FileCompressionOutcome] = []
        for url in validURLs {
            if let outcome = await processFile(
                url,
                source: .shortcut,
                reportStatus: false,
                notifyOnSuccess: false,
                videoPresetOverride: videoPresetOverride,
                profileOverride: selectedProfile,
                maximumVideoSizeMBOverride: maximumVideoSizeMB,
                maximumImageSizeMBOverride: maximumImageSizeMB,
                outputDestinationOverride: outputDestination
            ) {
                outcomes.append(outcome)
            }
        }
        guard !outcomes.isEmpty else { throw ShortcutCompressionError.noSupportedFiles }
        notifyFileCompression(outcomes)
        return outcomes.map(\.outputURL)
    }

    func shortcutProfile(identifier: String) -> SavedCompressionProfile? {
        CompressionProfileReference.resolve(identifier, savedProfiles: settings.savedProfiles)
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

    func copyLatestRecognizedText() {
        guard let text = latestRecognizedText, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func openOutput(for item: HistoryItem) {
        withOutputAccess(for: item) { _ = NSWorkspace.shared.open($0) }
    }

    func revealOutput(for item: HistoryItem) {
        withOutputAccess(for: item) { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    }

    private func withOutputAccess(for item: HistoryItem, perform: (URL) -> Void) {
        guard let url = item.resolvedOutputURL else {
            statusMessage = "压缩结果已移动或删除"
            return
        }
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "压缩结果已移动或删除"
            return
        }
        perform(url)
    }

    func undoClipboardCompression(notificationID: UUID? = nil) {
        guard let undoAction else { return }
        if let notificationID, notificationID != undoActionID {
            statusMessage = "这条撤销通知已过期"
            return
        }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == undoAction.changeCount else {
            self.undoAction = nil
            undoActionID = nil
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
            undoActionID = nil
            canUndoClipboardCompression = false
            statusMessage = "无法还原剪贴板"
            return
        }
        self.undoAction = nil
        undoActionID = nil
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
        if settings.clipboardMonitoringEnabled || settings.clipboardCollectionEnabled { clipboardMonitor.start() }
        restoreFolderWatchers()
    }

    private func updateClipboardMonitorState() {
        guard didStart else { return }
        if settings.clipboardMonitoringEnabled || settings.clipboardCollectionEnabled {
            configureClipboardMonitor()
            clipboardMonitor.start()
        } else {
            clipboardMonitor.stop()
        }
    }

    private func configureClipboardMonitor() {
        clipboardMonitor.onPayload = { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }
                if self.settings.clipboardCollectionEnabled { self.collectClipboardPayload(payload) }
                if self.settings.clipboardMonitoringEnabled { self.enqueueClipboardPayload(payload) }
            }
        }
        clipboardMonitor.onExternalChange = { [weak self] in
            Task { @MainActor in
                self?.undoAction = nil
                self?.undoActionID = nil
                self?.canUndoClipboardCompression = false
            }
        }
    }

    private func collectClipboardPayload(_ payload: ClipboardPayload) {
        guard clipboardCollection.append(payload) else { return }
        clipboardCollectionItems = clipboardCollection.items
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
        undoActionID = nil
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
            let options = settings.clipboardImageOptions
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
            let actionID = UUID()
            undoActionID = actionID
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
            sendCompressionNotice(.clipboard(
                fileCount: 1,
                originalBytes: Int64(result.originalByteCount),
                resultBytes: Int64(result.data.count),
                undoID: actionID
            ))
            if let nsImage = NSImage(data: result.data) {
                Task { @MainActor [weak self] in
                    self?.latestRecognizedText = await VisionTextExtractor.shared.extractText(from: nsImage)
                }
            }
            showFloatingPillHandler?()
        } catch {
            statusMessage = "剪贴板图片未处理：\(error.localizedDescription)"
        }
        finishClipboardTask()
    }

    private func processClipboardFiles(urls: [URL], changeCount: Int) async {
        var compressedURLs: [URL] = []
        var outcomes: [FileCompressionOutcome] = []
        for url in urls {
            if let outcome = await processFile(url, source: .automatic, reportStatus: false, notifyOnSuccess: false) {
                compressedURLs.append(outcome.outputURL)
                outcomes.append(outcome)
            } else {
                compressedURLs.append(url)
            }
        }

        let pasteboard = NSPasteboard.general
        if !outcomes.isEmpty, pasteboard.changeCount == changeCount {
            pasteboard.clearContents()
            guard pasteboard.writeObjects(filePasteboardItems(for: compressedURLs)) else {
                pasteboard.clearContents()
                _ = pasteboard.writeObjects(filePasteboardItems(for: urls))
                statusMessage = "无法更新剪贴板，原文件仍可用"
                finishClipboardTask()
                return
            }
            undoAction = .files(urls: urls, changeCount: pasteboard.changeCount)
            let actionID = UUID()
            undoActionID = actionID
            canUndoClipboardCompression = true
            let originalBytes = outcomes.reduce(Int64(0)) { $0 + $1.originalBytes }
            let resultBytes = outcomes.reduce(Int64(0)) { $0 + $1.resultBytes }
            let percent = savingPercent(originalBytes: originalBytes, resultBytes: resultBytes)
            statusMessage = "已省 \(percent)% · \(formattedSize(originalBytes)) → \(formattedSize(resultBytes))，可直接粘贴压缩副本"
            sendCompressionNotice(.clipboard(
                fileCount: outcomes.count,
                originalBytes: originalBytes,
                resultBytes: resultBytes,
                undoID: actionID
            ))
        }
        finishClipboardTask()
    }

    private func finishClipboardTask() {
        clipboardTaskRunning = false
        isProcessing = processingCount > 0
        runNextClipboardPayloadIfNeeded()
    }

    @discardableResult
    private func processFile(
        _ url: URL,
        source: FileSource,
        reportStatus: Bool = true,
        notifyOnSuccess: Bool = true,
        videoPresetOverride: VideoOutputPreset? = nil,
        securityScopeURL: URL? = nil,
        outputNameTemplate: String? = nil,
        profileOverride: SavedCompressionProfile? = nil,
        maximumVideoSizeMBOverride: Int? = nil,
        maximumImageSizeMBOverride: Double? = nil,
        outputDestinationOverride: CompressionOutputDestination? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> FileCompressionOutcome? {
        guard url.isFileURL else { return nil }
        let ext = url.pathExtension.lowercased()
        let isSVG = SVGCompressor.isSVG(url: url)
        let detectedImageType = ImageCompressor.detectedTypeIdentifier(at: url)
        let isImage = isSVG || detectedImageType != nil || ImageCompressor.typeIdentifier(forFileExtension: ext) != nil
        let isVideo = ext == "mov" || ext == "mp4" || ext == "m4v"
        let isPDF = ext == "pdf"
        guard isImage || isVideo || isPDF else {
            if reportStatus { statusMessage = "暂不支持 \(url.pathExtension.uppercased())" }
            return nil
        }
        if isPDF, !purchaseManager.isPro {
            if reportStatus { statusMessage = "PDF 压缩需要 DropSqueeze Pro" }
            requestPro(for: .pdfCompression)
            return nil
        }
        if requiresOutputFolderAuthorization, outputDestinationOverride != .sameAsSource {
            if reportStatus { statusMessage = "压缩结果文件夹无法访问，请重新选择保存位置" }
            return nil
        }
        let selectedImageOutputFormat = profileOverride?.imageFileOutputFormat ?? settings.imageFileOutputFormat
        if isImage, selectedImageOutputFormat == .webP, !purchaseManager.isPro {
            if reportStatus { statusMessage = "文件图片输出 WebP 需要 DropSqueeze Pro" }
            requestPro(for: .feature(.fileWebPOutput))
            return nil
        }
        if isImage, profileOverride?.retinaDownscaleEnabled == true, !purchaseManager.isPro {
            if reportStatus { statusMessage = "Retina 缩放配置需要 DropSqueeze Pro" }
            requestPro(for: .feature(.retinaDownscale))
            return nil
        }
        if ext == "mov",
           profileOverride?.gifConversionEnabled == true,
           !purchaseManager.isPro {
            if reportStatus { statusMessage = "MOV 转 GIF 配置需要 DropSqueeze Pro" }
            requestPro(for: .feature(.gifConversion))
            return nil
        }

        let processingPath = url.standardizedFileURL.path
        guard processingFilePaths.insert(processingPath).inserted else { return nil }
        await fileProcessingGate.acquire()
        defer {
            processingFilePaths.remove(processingPath)
            Task { await fileProcessingGate.release() }
        }

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

        let scopedSourceURL = securityScopeURL ?? url
        let startedAccess = scopedSourceURL.startAccessingSecurityScopedResource()
        defer { if startedAccess { scopedSourceURL.stopAccessingSecurityScopedResource() } }
        let selectedOutputDestination = outputDestinationOverride ?? .appDefault
        let scopedOutputFolder = selectedOutputDestination == .appDefault ? outputFolderURL : nil
        let outputDirectory = selectedOutputDestination.resolveDirectory(
            configuredOutputFolder: scopedOutputFolder,
            sourceURL: url
        )
        let startedOutputAccess = scopedOutputFolder?.startAccessingSecurityScopedResource() ?? false
        defer { if startedOutputAccess { scopedOutputFolder?.stopAccessingSecurityScopedResource() } }
        if scopedOutputFolder != nil {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  FileManager.default.isWritableFile(atPath: outputDirectory.path) else {
                requiresOutputFolderAuthorization = true
                if reportStatus { statusMessage = "无法写入压缩结果文件夹，请重新选择一个有写入权限的位置" }
                return nil
            }
        }
        processingCount += 1
        isProcessing = true
        let progressID = UUID()
        activeProgressID = progressID
        activeFileSource = source
        currentFileName = url.lastPathComponent
        let videoCanBeCancelled = isVideo && !(ext == "mov" && settings.gifConversionEnabled)
        let videoCancellation = videoCanBeCancelled ? VideoTranscoderCancellation() : nil
        activeVideoCancellation = videoCancellation
        currentProgress = videoCanBeCancelled ? 0 : nil
        defer {
            if activeProgressID == progressID {
                activeProgressID = nil
                currentFileName = nil
                currentProgress = nil
            }
            if activeVideoCancellation === videoCancellation { activeVideoCancellation = nil }
            activeFileSource = nil
            processingCount = max(0, processingCount - 1)
            isProcessing = clipboardTaskRunning || processingCount > 0
        }

        do {
            var outputURL: URL
            let originalSize: Int64
            let resultSize: Int64
            var didConvertImageFormat = false

            if isPDF {
                let compressed = try await Task.detached(priority: .utility) {
                    try PDFCompressor.compressFile(at: url, outputDirectory: outputDirectory)
                }.value
                guard let compressed else {
                    if reportStatus { statusMessage = "\(url.lastPathComponent)：没有更小的结果，原件保留" }
                    return nil
                }
                outputURL = compressed.outputURL
                originalSize = compressed.originalByteCount
                resultSize = compressed.resultByteCount
            } else if isSVG {
                let output = try await Task.detached(priority: .utility) { () throws -> (URL, CompressedSVG)? in
                    guard let compressed = try SVGCompressor.compressFile(at: url) else { return nil }
                    return (try SVGCompressor.writeCompressedSVG(compressed, beside: url, in: outputDirectory), compressed)
                }.value
                guard let (writtenURL, compressed) = output else {
                    if reportStatus { statusMessage = "\(url.lastPathComponent)：没有更小的结果，原件保留" }
                    return nil
                }
                outputURL = writtenURL
                originalSize = Int64(compressed.originalByteCount)
                resultSize = Int64(compressed.data.count)
                didConvertImageFormat = false
            } else if isImage {
                let options: ImageCompressionOptions
                if let profileOverride {
                    options = ImageCompressionOptions(
                        resizeRetinaTo1x: profileOverride.retinaDownscaleEnabled ?? settings.retinaDownscaleEnabled,
                        outputWebP: selectedImageOutputFormat == .webP,
                        outputTypeIdentifier: selectedImageOutputFormat.typeIdentifier,
                        maxPixelDimension: profileOverride.imageResizePreset.maxPixelDimension,
                        jpegQuality: profileOverride.imageQuality,
                        stripMetadata: profileOverride.stripImageMetadata,
                        maximumOutputSizeMB: maximumImageSizeMBOverride ?? profileOverride.imageMaximumSizeMB
                    )
                } else {
                    var currentOptions = settings.fileImageOptions
                    if let maximumImageSizeMBOverride {
                        currentOptions = ImageCompressionOptions(
                            resizeRetinaTo1x: currentOptions.resizeRetinaTo1x,
                            outputWebP: currentOptions.outputWebP,
                            outputTypeIdentifier: currentOptions.outputTypeIdentifier,
                            maxPixelDimension: currentOptions.maxPixelDimension,
                            jpegQuality: currentOptions.jpegQuality,
                            stripMetadata: currentOptions.stripMetadata,
                            maximumOutputSizeMB: maximumImageSizeMBOverride
                        )
                    }
                    options = currentOptions
                }
                guard !options.outputWebP || ImageCompressor.webPEncodingAvailable else {
                    throw ImageCompressionError.webPUnavailable
                }
                let output = try await Task.detached(priority: .utility) { () throws -> (URL, CompressedImage)? in
                    guard let compressed = try ImageCompressor.compressFile(at: url, options: options) else { return nil }
                    return (try ImageCompressor.writeCompressedFile(compressed, beside: url, in: outputDirectory), compressed)
                }.value
                guard let (writtenURL, compressed) = output else {
                    if reportStatus { statusMessage = "\(url.lastPathComponent)：没有更小的结果，原件保留" }
                    return nil
                }
                outputURL = writtenURL
                originalSize = Int64(compressed.originalByteCount)
                resultSize = Int64(compressed.data.count)
                didConvertImageFormat = ImageCompressor.typeIdentifier(forFileExtension: ext) != compressed.typeIdentifier
            } else {
                let selectedGIFConversion = profileOverride?.gifConversionEnabled ?? settings.gifConversionEnabled
                if ext == "mov", selectedGIFConversion {
                    outputURL = try await GIFGenerator.generateSmallerGIF(from: url, outputDirectory: outputDirectory)
                } else {
                    let selectedVideoProfile = profileOverride
                    outputURL = try await VideoTranscoder.transcodeToSmallerMP4(
                        url,
                        preset: videoPresetOverride ?? selectedVideoProfile?.videoOutputPreset ?? settings.videoOutputPreset,
                        codec: selectedVideoProfile?.videoCodecPreference ?? settings.videoCodecPreference,
                        bitrateTarget: selectedVideoProfile?.videoBitrateTarget ?? settings.videoBitrateTarget,
                        maximumFrameRate: selectedVideoProfile?.videoFrameRate ?? settings.videoFrameRate,
                        includesAudio: selectedVideoProfile?.videoIncludesAudio ?? settings.videoIncludesAudio,
                        maximumSizeMB: maximumVideoSizeMBOverride
                            ?? (selectedVideoProfile == nil ? settings.videoMaximumSizeMB : selectedVideoProfile?.videoMaximumSizeMB),
                        outputDirectory: outputDirectory,
                        cancellation: videoCancellation,
                        onProgress: { [weak self] progress in
                            Task { @MainActor [weak self] in
                                guard let self, self.activeProgressID == progressID else { return }
                                self.currentProgress = progress
                                onProgress?(progress)
                            }
                        }
                    )
                }
                originalSize = Self.fileSize(at: url)
                resultSize = Self.fileSize(at: outputURL)
            }

            if let outputNameTemplate {
                outputURL = try applyOutputNameTemplate(outputNameTemplate, to: outputURL, sourceURL: url)
            }

            let historyKind: HistoryItem.Kind = isPDF ? .pdfFile : (isImage ? .imageFile : .videoFile)
            let sourceDetails = await MediaTechnicalDetails.read(from: url, kind: historyKind)
            let outputDetails = await MediaTechnicalDetails.read(from: outputURL, kind: historyKind)

            record(HistoryItem(
                name: url.lastPathComponent,
                kind: historyKind,
                originalBytes: originalSize,
                resultBytes: resultSize,
                sourceURL: url,
                outputURL: outputURL,
                sourceDetails: sourceDetails,
                outputDetails: outputDetails
            ))
            generatedOutputPaths[outputURL.standardizedFileURL.path] = Date()
            generatedOutputPaths = generatedOutputPaths.filter { Date().timeIntervalSince($0.value) < 86_400 }
            succeeded = true
            if reportStatus {
                if didConvertImageFormat {
                    statusMessage = "图片格式已转换：\(outputURL.lastPathComponent)"
                } else {
                    let percent = savingPercent(originalBytes: originalSize, resultBytes: resultSize)
                    let mediaLabel = isPDF ? "PDF" : (isImage ? "图片" : "视频")
                    statusMessage = "\(mediaLabel)已省 \(percent)%：\(outputURL.lastPathComponent)"
                }
            }
            let outcome = FileCompressionOutcome(
                outputURL: outputURL,
                originalBytes: originalSize,
                resultBytes: resultSize,
                didConvertFormat: didConvertImageFormat
            )
            if notifyOnSuccess { notifyFileCompression([outcome]) }
            if isImage && !isSVG {
                let targetURL = outputURL
                Task { @MainActor [weak self] in
                    self?.latestRecognizedText = await VisionTextExtractor.shared.extractText(from: targetURL)
                }
            }
            showFloatingPillHandler?()
            return outcome
        } catch {
            if reportStatus {
                if let videoError = error as? VideoTranscodingError,
                   case .cancelled = videoError {
                    statusMessage = "已取消：\(url.lastPathComponent)"
                } else {
                    statusMessage = "\(url.lastPathComponent)：\(error.localizedDescription)"
                }
            }
            return nil
        }
    }

    private func record(_ item: HistoryItem) {
        history.insert(item, at: 0)
        history = Array(history.prefix(10))
        defaults.set(try? PropertyListEncoder().encode(history), forKey: historyKey)
        defaults.set(totalSavedBytes + item.savedBytes, forKey: totalSavedKey)
        defaults.set(totalCompressionCount + 1, forKey: totalCountKey)
        usageTracker.recordSavedBytes(item.savedBytes)
        if let date = defaults.object(forKey: dailyCountDateKey) as? Date,
           Calendar.current.isDateInToday(date) {
            defaults.set(defaults.integer(forKey: dailyCountKey) + 1, forKey: dailyCountKey)
        } else {
            defaults.set(Date(), forKey: dailyCountDateKey)
            defaults.set(1, forKey: dailyCountKey)
        }
    }

    private func notifyFileCompression(_ outcomes: [FileCompressionOutcome]) {
        guard !outcomes.isEmpty else { return }
        let originalBytes = outcomes.reduce(Int64(0)) { $0 + $1.originalBytes }
        let resultBytes = outcomes.reduce(Int64(0)) { $0 + $1.resultBytes }
        sendCompressionNotice(.files(
            fileCount: outcomes.count,
            originalBytes: originalBytes,
            resultBytes: resultBytes,
            includesFormatConversion: outcomes.contains(where: \.didConvertFormat)
        ))
    }

    private func sendCompressionNotice(_ notice: CompressionNotice) {
        playCompletionFeedback()
        guard settings.notificationsEnabled else { return }
        compressionNotificationHandler?(notice)
    }

    func playCompletionFeedback() {
        CompressionFeedbackController.shared.playFeedback(
            soundName: settings.completionSoundEnabled ? settings.completionSoundName : nil,
            haptics: settings.hapticFeedbackEnabled
        )
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

        let watcher = DirectoryWatcher(directoryURL: url, rule: folder.rule) { [weak self] urls in
            guard let self else { return }
            let profile = folder.rule.resolvedCompressionProfile(savedProfiles: self.settings.savedProfiles)
            if !folder.rule.usesCurrentCompressionProfile, profile == nil {
                self.statusMessage = "监控文件夹配置已删除，请为 \(url.lastPathComponent) 选择其他配置"
                return
            }
            for candidate in urls where self.generatedOutputPaths[candidate.standardizedFileURL.path] == nil {
                Task {
                    await self.processFile(
                        candidate,
                        source: .automatic,
                        securityScopeURL: url,
                        outputNameTemplate: folder.rule.outputNameTemplate,
                        profileOverride: profile
                    )
                }
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
        monitoredFolders = folderBookmarks.map { MonitoredFolder(id: $0.id, path: $0.path, rule: $0.rule) }
    }

    func applyOutputNameTemplate(_ template: String, to outputURL: URL, sourceURL: URL) throws -> URL {
        let inputStem = sourceURL.deletingPathExtension().lastPathComponent
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "yyyyMMdd-HHmmss"
        var stem = template
            .replacingOccurrences(of: "{name}", with: inputStem)
            .replacingOccurrences(of: "{date}", with: date.string(from: Date()))
        stem = String(stem.filter { $0 != "/" && $0 != ":" }.prefix(120))
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if stem.isEmpty || stem == "." || stem == ".." { stem = "compressed" }
        let ext = outputURL.pathExtension
        let directory = outputURL.deletingLastPathComponent()
        var suffix = 1
        while true {
            let candidateName = suffix == 1 ? "\(stem).\(ext)" : "\(stem)-\(suffix).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if candidate.standardizedFileURL == outputURL.standardizedFileURL { return outputURL }
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                try FileManager.default.moveItem(at: outputURL, to: candidate)
                return candidate
            }
            suffix += 1
        }
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
