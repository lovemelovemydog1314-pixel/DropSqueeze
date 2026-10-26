import Combine
import Foundation
import UniformTypeIdentifiers

enum ProFeature: String, CaseIterable, Identifiable, Sendable, Equatable {
    case retinaDownscale
    case clipboardWebPOutput
    case fileWebPOutput
    case gifConversion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .retinaDownscale: return "Retina 截图缩至 1×"
        case .clipboardWebPOutput: return "剪贴板图片转为 WebP"
        case .fileWebPOutput: return "文件输出转为 WebP"
        case .gifConversion: return "录屏自动转为 GIF"
        }
    }

    var detail: String {
        switch self {
        case .retinaDownscale: return "根据图片 DPI 元数据识别 2× 截图并缩小到标准尺寸。"
        case .clipboardWebPOutput: return "剪贴板图片以 WebP 替换；部分应用可能不接受 WebP 剪贴板内容。"
        case .fileWebPOutput: return "静态图片文件另存为 WebP；动画 GIF 保留动画并继续输出为 GIF。"
        case .gifConversion: return "将不超过 15 秒的 MOV 录屏转为最高 30 帧/秒的 GIF。"
        }
    }
}

enum FolderWatchScope: String, CaseIterable, Codable, Identifiable, Equatable {
    case screenshotsAndRecordings
    case images
    case videos
    case allSupported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshotsAndRecordings: return "截图和录屏"
        case .images: return "所有图片"
        case .videos: return "所有视频"
        case .allSupported: return "图片、视频和 PDF"
        }
    }
}

struct FolderWatchRule: Codable, Equatable {
    var scope: FolderWatchScope = .screenshotsAndRecordings
    var includeSubfolders = false
    var filenameContains = ""
    var maximumFileSizeMB: Int?
    var outputNameTemplate = "{name}-compressed"

    func accepts(_ url: URL, size: Int64) -> Bool {
        let ext = url.pathExtension.lowercased()
        let isKnownImageExtension = ImageCompressor.typeIdentifier(forFileExtension: ext) != nil
        let isImage = isKnownImageExtension
            || (!isKnownImageExtension && !["mov", "mp4", "m4v", "pdf"].contains(ext)
                && ImageCompressor.detectedTypeIdentifier(at: url) != nil)
        let isVideo = ["mov", "mp4", "m4v"].contains(ext)
        let isPDF = ext == "pdf"
        let stem = url.deletingPathExtension().lastPathComponent
        let lowerStem = stem.lowercased()
        guard !lowerStem.hasSuffix("-compressed"), !lowerStem.contains("-compressed-") else { return false }
        if !filenameContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !lowerStem.localizedCaseInsensitiveContains(filenameContains.trimmingCharacters(in: .whitespacesAndNewlines)) { return false }
        if let maximumFileSizeMB, maximumFileSizeMB > 0,
           Double(size) > Double(maximumFileSizeMB) * 1_000_000 { return false }
        switch scope {
        case .screenshotsAndRecordings:
            let screenshot = ["screen shot", "screenshot", "截屏", "屏幕快照", "屏幕截图", "屏幕截屏"]
                .contains(where: lowerStem.contains)
            let recording = ["screen recording", "屏幕录制", "录屏"]
                .contains(where: lowerStem.contains)
            return (screenshot && isImage) || (recording && ext == "mov")
        case .images: return isImage
        case .videos: return isVideo
        case .allSupported: return isImage || isVideo || isPDF
        }
    }
}

struct FolderBookmark: Codable, Identifiable {
    let id: UUID
    let path: String
    var bookmarkData: Data
    var rule: FolderWatchRule

    init(id: UUID = UUID(), path: String, bookmarkData: Data, rule: FolderWatchRule = FolderWatchRule()) {
        self.id = id
        self.path = path
        self.bookmarkData = bookmarkData
        self.rule = rule
    }

    private enum CodingKeys: String, CodingKey { case id, path, bookmarkData, rule }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        bookmarkData = try container.decode(Data.self, forKey: .bookmarkData)
        rule = try container.decodeIfPresent(FolderWatchRule.self, forKey: .rule) ?? FolderWatchRule()
    }
}

struct MonitoredFolder: Identifiable, Equatable {
    let id: UUID
    let path: String
    var rule: FolderWatchRule = FolderWatchRule()

    var displayName: String { URL(fileURLWithPath: path).lastPathComponent }
}

enum PaywallReason: Equatable {
    case general
    case imageQuota
    case videoQuota
    case pdfCompression
    case secondFolder
    case batchCompression
    case feature(ProFeature)

    var title: String {
        switch self {
        case .general: return "解锁 DropSqueeze Pro"
        case .imageQuota: return "今日免费图片额度已用完"
        case .videoQuota: return "今日免费视频额度已用完"
        case .pdfCompression: return "解锁 PDF 压缩"
        case .secondFolder: return "添加第二个监控文件夹"
        case .batchCompression: return "批量压缩属于 Pro 功能"
        case .feature(let feature): return "解锁：\(feature.title)"
        }
    }

    var detail: String {
        switch self {
        case .general: return "解锁无限自动压缩、批量处理、多文件夹监控，以及 WebP、Retina、GIF 和 PDF 压缩。"
        case .imageQuota: return "Pro 可无限自动压缩剪贴板与文件夹中的图片。"
        case .videoQuota: return "Pro 可无限自动转码录屏，并启用高阶视频规则。"
        case .pdfCompression: return "Pro 可优化 PDF 中的图像并生成保留原件的压缩副本；加密或数字签名文件会跳过。"
        case .secondFolder: return "免费版可监控一个文件夹；Pro 可监控多个文件夹。"
        case .batchCompression: return "免费版可拖入单个文件；Pro 可一次处理多个文件。"
        case .feature(let feature): return feature.detail
        }
    }
}

struct PaywallRequest: Identifiable {
    let id = UUID()
    let reason: PaywallReason
    let weeklySavedBytes: Int64
}

enum ImageResizePreset: String, CaseIterable, Identifiable, Codable, Sendable, Equatable {
    case original
    case max4096
    case max2560
    case max1920

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "保留原尺寸"
        case .max4096: return "最长边 4096 像素"
        case .max2560: return "最长边 2560 像素"
        case .max1920: return "最长边 1920 像素"
        }
    }

    var maxPixelDimension: Int? {
        switch self {
        case .original: return nil
        case .max4096: return 4096
        case .max2560: return 2560
        case .max1920: return 1920
        }
    }
}

enum ImageFileOutputFormat: String, CaseIterable, Identifiable, Codable, Sendable, Equatable {
    case original
    case jpeg
    case heic
    case png
    case webP

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "保持原格式"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .png: return "PNG"
        case .webP: return "WebP · Pro"
        }
    }

    var typeIdentifier: String? {
        switch self {
        case .original: return nil
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .png: return UTType.png.identifier
        case .webP: return UTType.webP.identifier
        }
    }
}

struct ImageCompressionOptions: Sendable {
    let resizeRetinaTo1x: Bool
    let outputWebP: Bool
    let outputTypeIdentifier: String?
    let maxPixelDimension: Int?
    let jpegQuality: Double
    let stripMetadata: Bool

    static let standard = ImageCompressionOptions(
        resizeRetinaTo1x: false,
        outputWebP: false,
        outputTypeIdentifier: nil,
        maxPixelDimension: nil,
        jpegQuality: 0.88,
        stripMetadata: false
    )
}

enum CompressionScenario: String, CaseIterable, Codable, Identifiable, Sendable {
    case balanced
    case messaging
    case highQuality
    case emailAttachment
    case webPublishing
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "均衡"
        case .messaging: return "聊天分享"
        case .highQuality: return "高画质"
        case .emailAttachment: return "邮件附件"
        case .webPublishing: return "网页图片"
        case .archive: return "清晰归档"
        }
    }

    var detail: String {
        switch self {
        case .balanced: return "日常图片与 720p 视频"
        case .messaging: return "缩小图片并优先控制视频体积"
        case .highQuality: return "保留高分辨率与图像细节"
        case .emailAttachment: return "图片清除位置等信息；视频优先控制在 10 MB 内"
        case .webPublishing: return "图片输出 WebP 并移除多余元数据"
        case .archive: return "保留原始图像信息并优先保存细节"
        }
    }

    var requiredProFeature: ProFeature? {
        self == .webPublishing ? .fileWebPOutput : nil
    }

    var profile: SavedCompressionProfile {
        let imageResizePreset: ImageResizePreset
        let imageQuality: Double
        let imageFileOutputFormat: ImageFileOutputFormat
        let stripImageMetadata: Bool
        let videoOutputPreset: VideoOutputPreset
        let videoCodecPreference: VideoCodecPreference
        let videoBitrateTarget: VideoBitrateTarget
        let videoFrameRate: VideoFrameRate
        switch self {
        case .balanced:
            imageResizePreset = .max2560
            imageQuality = 0.84
            imageFileOutputFormat = .original
            stripImageMetadata = false
            videoOutputPreset = .standard720p
            videoCodecPreference = .automatic
            videoBitrateTarget = .balanced
            videoFrameRate = .original
        case .messaging:
            imageResizePreset = .max1920
            imageQuality = 0.76
            imageFileOutputFormat = .jpeg
            stripImageMetadata = true
            videoOutputPreset = .compact10MB
            videoCodecPreference = .hevc
            videoBitrateTarget = .economy
            videoFrameRate = .fps30
        case .highQuality:
            imageResizePreset = .max4096
            imageQuality = 0.92
            imageFileOutputFormat = .original
            stripImageMetadata = false
            videoOutputPreset = .high1080p
            videoCodecPreference = .automatic
            videoBitrateTarget = .highQuality
            videoFrameRate = .original
        case .emailAttachment:
            imageResizePreset = .max1920
            imageQuality = 0.72
            imageFileOutputFormat = .jpeg
            stripImageMetadata = true
            videoOutputPreset = .compact10MB
            videoCodecPreference = .h264
            videoBitrateTarget = .economy
            videoFrameRate = .fps30
        case .webPublishing:
            imageResizePreset = .max2560
            imageQuality = 0.82
            imageFileOutputFormat = .webP
            stripImageMetadata = true
            videoOutputPreset = .standard720p
            videoCodecPreference = .h264
            videoBitrateTarget = .balanced
            videoFrameRate = .fps30
        case .archive:
            imageResizePreset = .max4096
            imageQuality = 0.96
            imageFileOutputFormat = .original
            stripImageMetadata = false
            videoOutputPreset = .high1080p
            videoCodecPreference = .hevc
            videoBitrateTarget = .highQuality
            videoFrameRate = .original
        }
        return SavedCompressionProfile(
            name: title,
            imageResizePreset: imageResizePreset,
            imageQuality: imageQuality,
            imageFileOutputFormat: imageFileOutputFormat,
            stripImageMetadata: stripImageMetadata,
            videoOutputPreset: videoOutputPreset,
            videoCodecPreference: videoCodecPreference,
            videoBitrateTarget: videoBitrateTarget,
            videoFrameRate: videoFrameRate,
            videoIncludesAudio: true,
            videoMaximumSizeMB: nil
        )
    }
}

enum CompressionOutputDestination: String, CaseIterable, Codable, Identifiable, Sendable {
    case appDefault
    case sameAsSource

    var id: String { rawValue }

    func resolveDirectory(configuredOutputFolder: URL?, sourceURL: URL) -> URL {
        if self == .appDefault, let configuredOutputFolder { return configuredOutputFolder }
        return sourceURL.deletingLastPathComponent()
    }
}

enum CompressionProfileReference {
    static let currentIdentifier = "current"

    static func identifier(for scenario: CompressionScenario) -> String {
        "scenario:\(scenario.rawValue)"
    }

    static func identifier(for profile: SavedCompressionProfile) -> String {
        "saved:\(profile.id.uuidString)"
    }

    static func isCurrent(_ identifier: String) -> Bool {
        identifier == currentIdentifier
    }

    static func resolve(_ identifier: String, savedProfiles: [SavedCompressionProfile]) -> SavedCompressionProfile? {
        if identifier.hasPrefix("scenario:"),
           let scenario = CompressionScenario(rawValue: String(identifier.dropFirst("scenario:".count))) {
            return scenario.profile
        }
        guard identifier.hasPrefix("saved:"),
              let id = UUID(uuidString: String(identifier.dropFirst("saved:".count))) else { return nil }
        return savedProfiles.first(where: { $0.id == id })
    }
}

struct SavedCompressionProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var imageResizePreset: ImageResizePreset
    var imageQuality: Double
    var imageFileOutputFormat: ImageFileOutputFormat
    var stripImageMetadata: Bool
    var videoOutputPreset: VideoOutputPreset
    var videoCodecPreference: VideoCodecPreference
    var videoBitrateTarget: VideoBitrateTarget
    var videoFrameRate: VideoFrameRate
    var videoIncludesAudio: Bool
    var videoMaximumSizeMB: Int?
    var retinaDownscaleEnabled: Bool?
    var gifConversionEnabled: Bool?

    init(id: UUID = UUID(), name: String, imageResizePreset: ImageResizePreset, imageQuality: Double,
         imageFileOutputFormat: ImageFileOutputFormat, stripImageMetadata: Bool, videoOutputPreset: VideoOutputPreset,
         videoCodecPreference: VideoCodecPreference, videoBitrateTarget: VideoBitrateTarget,
         videoFrameRate: VideoFrameRate, videoIncludesAudio: Bool, videoMaximumSizeMB: Int? = nil,
         retinaDownscaleEnabled: Bool? = nil, gifConversionEnabled: Bool? = nil) {
        self.id = id
        self.name = name
        self.imageResizePreset = imageResizePreset
        self.imageQuality = imageQuality
        self.imageFileOutputFormat = imageFileOutputFormat
        self.stripImageMetadata = stripImageMetadata
        self.videoOutputPreset = videoOutputPreset
        self.videoCodecPreference = videoCodecPreference
        self.videoBitrateTarget = videoBitrateTarget
        self.videoFrameRate = videoFrameRate
        self.videoIncludesAudio = videoIncludesAudio
        self.videoMaximumSizeMB = videoMaximumSizeMB
        self.retinaDownscaleEnabled = retinaDownscaleEnabled
        self.gifConversionEnabled = gifConversionEnabled
    }

    var requiredProFeature: ProFeature? {
        if imageFileOutputFormat == .webP { return .fileWebPOutput }
        if retinaDownscaleEnabled == true { return .retinaDownscale }
        if gifConversionEnabled == true { return .gifConversion }
        return nil
    }
}

@MainActor
final class RulesSettings: ObservableObject {
    @Published private(set) var clipboardMonitoringEnabled: Bool
    @Published private(set) var folderMonitoringEnabled: Bool
    @Published private(set) var retinaDownscaleEnabled: Bool
    @Published private(set) var clipboardWebPOutputEnabled: Bool
    @Published private(set) var imageFileOutputFormat: ImageFileOutputFormat
    @Published private(set) var gifConversionEnabled: Bool
    @Published private(set) var imageResizePreset: ImageResizePreset
    @Published private(set) var imageQuality: Double
    @Published private(set) var stripImageMetadata: Bool
    @Published private(set) var videoOutputPreset: VideoOutputPreset
    @Published private(set) var videoCodecPreference: VideoCodecPreference
    @Published private(set) var videoBitrateTarget: VideoBitrateTarget
    @Published private(set) var videoFrameRate: VideoFrameRate
    @Published private(set) var videoIncludesAudio: Bool
    @Published private(set) var videoMaximumSizeMB: Int?
    @Published private(set) var notificationsEnabled: Bool
    @Published private(set) var savedProfiles: [SavedCompressionProfile]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        clipboardMonitoringEnabled = defaults.object(forKey: "clipboardMonitoringEnabled") as? Bool ?? true
        folderMonitoringEnabled = defaults.object(forKey: "folderMonitoringEnabled") as? Bool ?? true
        retinaDownscaleEnabled = defaults.bool(forKey: "retinaDownscaleEnabled")
        let legacyWebPOutputEnabled = defaults.bool(forKey: "webPOutputEnabled")
        clipboardWebPOutputEnabled = defaults.object(forKey: "clipboardWebPOutputEnabled") as? Bool ?? legacyWebPOutputEnabled
        let storedFileOutputFormat = defaults.string(forKey: "imageFileOutputFormat")
        imageFileOutputFormat = ImageFileOutputFormat(rawValue: storedFileOutputFormat ?? "")
            ?? ((defaults.object(forKey: "fileWebPOutputEnabled") as? Bool ?? legacyWebPOutputEnabled) ? .webP : .original)
        gifConversionEnabled = defaults.bool(forKey: "gifConversionEnabled")
        imageResizePreset = ImageResizePreset(rawValue: defaults.string(forKey: "imageResizePreset") ?? "") ?? .original
        imageQuality = min(0.96, max(0.4, defaults.object(forKey: "imageQuality") as? Double ?? 0.88))
        stripImageMetadata = defaults.bool(forKey: "stripImageMetadata")
        videoOutputPreset = VideoOutputPreset(rawValue: defaults.string(forKey: "videoOutputPreset") ?? "") ?? .standard720p
        videoCodecPreference = VideoCodecPreference(rawValue: defaults.string(forKey: "videoCodecPreference") ?? "") ?? .automatic
        videoBitrateTarget = VideoBitrateTarget(rawValue: defaults.integer(forKey: "videoBitrateTarget")) ?? .automatic
        videoFrameRate = VideoFrameRate(rawValue: defaults.integer(forKey: "videoFrameRate")) ?? .original
        videoIncludesAudio = defaults.object(forKey: "videoIncludesAudio") as? Bool ?? true
        let savedMaximumSizeMB = defaults.object(forKey: "videoMaximumSizeMB") as? Int
        videoMaximumSizeMB = savedMaximumSizeMB.flatMap { (1...5_000).contains($0) ? $0 : nil }
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "savedCompressionProfiles"),
           let profiles = try? PropertyListDecoder().decode([SavedCompressionProfile].self, from: data) {
            savedProfiles = profiles
        } else {
            savedProfiles = []
        }
    }

    var clipboardImageOptions: ImageCompressionOptions {
        ImageCompressionOptions(
            resizeRetinaTo1x: retinaDownscaleEnabled,
            outputWebP: clipboardWebPOutputEnabled,
            outputTypeIdentifier: nil,
            maxPixelDimension: imageResizePreset.maxPixelDimension,
            jpegQuality: imageQuality,
            stripMetadata: stripImageMetadata
        )
    }

    var fileImageOptions: ImageCompressionOptions {
        ImageCompressionOptions(
            resizeRetinaTo1x: retinaDownscaleEnabled,
            outputWebP: imageFileOutputFormat == .webP,
            outputTypeIdentifier: imageFileOutputFormat.typeIdentifier,
            maxPixelDimension: imageResizePreset.maxPixelDimension,
            jpegQuality: imageQuality,
            stripMetadata: stripImageMetadata
        )
    }

    var fileWebPOutputEnabled: Bool { imageFileOutputFormat == .webP }

    func isEnabled(_ feature: ProFeature) -> Bool {
        switch feature {
        case .retinaDownscale: return retinaDownscaleEnabled
        case .clipboardWebPOutput: return clipboardWebPOutputEnabled
        case .fileWebPOutput: return imageFileOutputFormat == .webP
        case .gifConversion: return gifConversionEnabled
        }
    }

    func setClipboardMonitoringEnabled(_ enabled: Bool) {
        clipboardMonitoringEnabled = enabled
        defaults.set(enabled, forKey: "clipboardMonitoringEnabled")
    }

    func setFolderMonitoringEnabled(_ enabled: Bool) {
        folderMonitoringEnabled = enabled
        defaults.set(enabled, forKey: "folderMonitoringEnabled")
    }

    func set(_ feature: ProFeature, enabled: Bool) {
        switch feature {
        case .retinaDownscale:
            retinaDownscaleEnabled = enabled
            defaults.set(enabled, forKey: "retinaDownscaleEnabled")
        case .clipboardWebPOutput:
            clipboardWebPOutputEnabled = enabled
            defaults.set(enabled, forKey: "clipboardWebPOutputEnabled")
        case .fileWebPOutput:
            setImageFileOutputFormat(enabled ? .webP : .original)
        case .gifConversion:
            gifConversionEnabled = enabled
            defaults.set(enabled, forKey: "gifConversionEnabled")
        }
    }

    func setVideoOutputPreset(_ preset: VideoOutputPreset) {
        videoOutputPreset = preset
        defaults.set(preset.rawValue, forKey: "videoOutputPreset")
    }

    func setVideoCodecPreference(_ preference: VideoCodecPreference) {
        videoCodecPreference = preference
        defaults.set(preference.rawValue, forKey: "videoCodecPreference")
    }

    func setVideoBitrateTarget(_ target: VideoBitrateTarget) {
        videoBitrateTarget = target
        defaults.set(target.rawValue, forKey: "videoBitrateTarget")
    }

    func setVideoFrameRate(_ frameRate: VideoFrameRate) {
        videoFrameRate = frameRate
        defaults.set(frameRate.rawValue, forKey: "videoFrameRate")
    }

    func setVideoIncludesAudio(_ includesAudio: Bool) {
        videoIncludesAudio = includesAudio
        defaults.set(includesAudio, forKey: "videoIncludesAudio")
    }

    func setVideoMaximumSizeMB(_ sizeMB: Int?) {
        let validSizeMB = sizeMB.flatMap { (1...5_000).contains($0) ? $0 : nil }
        videoMaximumSizeMB = validSizeMB
        if let validSizeMB {
            defaults.set(validSizeMB, forKey: "videoMaximumSizeMB")
        } else {
            defaults.removeObject(forKey: "videoMaximumSizeMB")
        }
    }

    func setImageResizePreset(_ preset: ImageResizePreset) {
        imageResizePreset = preset
        defaults.set(preset.rawValue, forKey: "imageResizePreset")
    }

    func setImageFileOutputFormat(_ format: ImageFileOutputFormat) {
        imageFileOutputFormat = format
        defaults.set(format.rawValue, forKey: "imageFileOutputFormat")
        defaults.set(format == .webP, forKey: "fileWebPOutputEnabled")
    }

    func setImageQuality(_ quality: Double) {
        imageQuality = min(0.96, max(0.4, quality))
        defaults.set(imageQuality, forKey: "imageQuality")
    }

    func setStripImageMetadata(_ enabled: Bool) {
        stripImageMetadata = enabled
        defaults.set(enabled, forKey: "stripImageMetadata")
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: "notificationsEnabled")
    }

    func applyScenario(_ scenario: CompressionScenario) {
        apply(scenario.profile)
    }

    @discardableResult
    func saveCurrentProfile(name: String) -> SavedCompressionProfile? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }
        let profile = SavedCompressionProfile(
            name: normalizedName,
            imageResizePreset: imageResizePreset,
            imageQuality: imageQuality,
            imageFileOutputFormat: imageFileOutputFormat,
            stripImageMetadata: stripImageMetadata,
            videoOutputPreset: videoOutputPreset,
            videoCodecPreference: videoCodecPreference,
            videoBitrateTarget: videoBitrateTarget,
            videoFrameRate: videoFrameRate,
            videoIncludesAudio: videoIncludesAudio,
            videoMaximumSizeMB: videoMaximumSizeMB,
            retinaDownscaleEnabled: retinaDownscaleEnabled,
            gifConversionEnabled: gifConversionEnabled
        )
        savedProfiles.append(profile)
        persistProfiles()
        return profile
    }

    func apply(_ profile: SavedCompressionProfile) {
        setImageResizePreset(profile.imageResizePreset)
        setImageQuality(profile.imageQuality)
        setImageFileOutputFormat(profile.imageFileOutputFormat)
        setStripImageMetadata(profile.stripImageMetadata)
        setVideoOutputPreset(profile.videoOutputPreset)
        setVideoCodecPreference(profile.videoCodecPreference)
        setVideoBitrateTarget(profile.videoBitrateTarget)
        setVideoFrameRate(profile.videoFrameRate)
        setVideoIncludesAudio(profile.videoIncludesAudio)
        setVideoMaximumSizeMB(profile.videoMaximumSizeMB)
        if let enabled = profile.retinaDownscaleEnabled { set(.retinaDownscale, enabled: enabled) }
        if let enabled = profile.gifConversionEnabled { set(.gifConversion, enabled: enabled) }
    }

    func deleteProfile(_ id: UUID) {
        savedProfiles.removeAll { $0.id == id }
        persistProfiles()
    }

    private func persistProfiles() {
        defaults.set(try? PropertyListEncoder().encode(savedProfiles), forKey: "savedCompressionProfiles")
    }

    func disableProFeatures() {
        set(.retinaDownscale, enabled: false)
        set(.clipboardWebPOutput, enabled: false)
        set(.fileWebPOutput, enabled: false)
        set(.gifConversion, enabled: false)
    }
}
