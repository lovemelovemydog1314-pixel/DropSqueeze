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

struct FolderBookmark: Codable, Identifiable {
    let id: UUID
    let path: String
    var bookmarkData: Data

    init(id: UUID = UUID(), path: String, bookmarkData: Data) {
        self.id = id
        self.path = path
        self.bookmarkData = bookmarkData
    }
}

struct MonitoredFolder: Identifiable, Equatable {
    let id: UUID
    let path: String

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

enum ImageResizePreset: String, CaseIterable, Identifiable, Codable, Sendable {
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

enum ImageFileOutputFormat: String, CaseIterable, Identifiable, Codable, Sendable {
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
    @Published private(set) var notificationsEnabled: Bool

    private let defaults = UserDefaults.standard

    init() {
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
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
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

    func disableProFeatures() {
        set(.retinaDownscale, enabled: false)
        set(.clipboardWebPOutput, enabled: false)
        set(.fileWebPOutput, enabled: false)
        set(.gifConversion, enabled: false)
    }
}
