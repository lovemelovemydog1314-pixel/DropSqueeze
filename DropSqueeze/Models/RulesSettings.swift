import Combine
import Foundation

enum ProFeature: String, CaseIterable, Identifiable, Sendable, Equatable {
    case retinaDownscale
    case webPOutput
    case gifConversion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .retinaDownscale: return "Retina 截图缩至 1×"
        case .webPOutput: return "图片自动转为 WebP"
        case .gifConversion: return "录屏自动转为 GIF"
        }
    }

    var detail: String {
        switch self {
        case .retinaDownscale: return "根据图片 DPI 元数据识别 2× 截图并缩小到标准尺寸。"
        case .webPOutput: return "剪贴板和文件输出为 WebP；部分应用可能不接受 WebP 剪贴板格式。"
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
    case secondFolder
    case batchCompression
    case feature(ProFeature)

    var title: String {
        switch self {
        case .general: return "解锁 DropSqueeze Pro"
        case .imageQuota: return "今日免费图片额度已用完"
        case .videoQuota: return "今日免费视频额度已用完"
        case .secondFolder: return "添加第二个监控文件夹"
        case .batchCompression: return "批量压缩属于 Pro 功能"
        case .feature(let feature): return "解锁：\(feature.title)"
        }
    }

    var detail: String {
        switch self {
        case .general: return "解锁无限自动压缩、批量处理、多文件夹监控，以及 WebP、Retina 和 GIF 规则。"
        case .imageQuota: return "Pro 可无限自动压缩剪贴板与文件夹中的图片。"
        case .videoQuota: return "Pro 可无限自动转码录屏，并启用高阶视频规则。"
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

struct ImageCompressionOptions: Sendable {
    let resizeRetinaTo1x: Bool
    let outputWebP: Bool
    let jpegQuality: Double

    static let standard = ImageCompressionOptions(resizeRetinaTo1x: false, outputWebP: false, jpegQuality: 0.88)
}

@MainActor
final class RulesSettings: ObservableObject {
    @Published private(set) var clipboardMonitoringEnabled: Bool
    @Published private(set) var folderMonitoringEnabled: Bool
    @Published private(set) var retinaDownscaleEnabled: Bool
    @Published private(set) var webPOutputEnabled: Bool
    @Published private(set) var gifConversionEnabled: Bool

    private let defaults = UserDefaults.standard

    init() {
        clipboardMonitoringEnabled = defaults.object(forKey: "clipboardMonitoringEnabled") as? Bool ?? true
        folderMonitoringEnabled = defaults.object(forKey: "folderMonitoringEnabled") as? Bool ?? true
        retinaDownscaleEnabled = defaults.bool(forKey: "retinaDownscaleEnabled")
        webPOutputEnabled = defaults.bool(forKey: "webPOutputEnabled")
        gifConversionEnabled = defaults.bool(forKey: "gifConversionEnabled")
    }

    var imageOptions: ImageCompressionOptions {
        ImageCompressionOptions(
            resizeRetinaTo1x: retinaDownscaleEnabled,
            outputWebP: webPOutputEnabled,
            jpegQuality: 0.88
        )
    }

    func isEnabled(_ feature: ProFeature) -> Bool {
        switch feature {
        case .retinaDownscale: return retinaDownscaleEnabled
        case .webPOutput: return webPOutputEnabled
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
        case .webPOutput:
            webPOutputEnabled = enabled
            defaults.set(enabled, forKey: "webPOutputEnabled")
        case .gifConversion:
            gifConversionEnabled = enabled
            defaults.set(enabled, forKey: "gifConversionEnabled")
        }
    }

    func disableProFeatures() {
        set(.retinaDownscale, enabled: false)
        set(.webPOutput, enabled: false)
        set(.gifConversion, enabled: false)
    }
}
