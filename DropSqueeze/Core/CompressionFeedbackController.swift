import AppKit

enum CompressionFeedbackSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case pop = "Pop"
    case glass = "Glass"
    case tink = "Tink"
    case blow = "Blow"
    case ping = "Ping"
    case purr = "Purr"
    case none = "None"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pop: return "清脆气泡 (Pop)"
        case .glass: return "轻盈玻璃 (Glass)"
        case .tink: return "金属快门 (Tink)"
        case .blow: return "微风微响 (Blow)"
        case .ping: return "清澈提示 (Ping)"
        case .purr: return "柔和鸣响 (Purr)"
        case .none: return "静音"
        }
    }
}

@MainActor
final class CompressionFeedbackController {
    static let shared = CompressionFeedbackController()

    func playFeedback(soundName: String? = "Pop", haptics: Bool = true) {
        if haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        guard let soundName, soundName != CompressionFeedbackSound.none.rawValue else { return }
        NSSound(named: soundName)?.play()
    }
}
