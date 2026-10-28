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

    @MainActor
    var title: String {
        switch self {
        case .pop: return L10n.tr("清脆气泡 (Pop)")
        case .glass: return L10n.tr("轻盈玻璃 (Glass)")
        case .tink: return L10n.tr("金属快门 (Tink)")
        case .blow: return L10n.tr("微风微响 (Blow)")
        case .ping: return L10n.tr("清澈提示 (Ping)")
        case .purr: return L10n.tr("柔和鸣响 (Purr)")
        case .none: return L10n.tr("静音")
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
