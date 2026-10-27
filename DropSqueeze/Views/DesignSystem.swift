import AppKit
import SwiftUI

// MARK: - Design Tokens & Springs

enum DesignTokens {
    static let quickSpring: Animation = .spring(response: 0.24, dampingFraction: 0.82)
    static let smoothSpring: Animation = .spring(response: 0.32, dampingFraction: 0.86)
    static let bouncySpring: Animation = .spring(response: 0.36, dampingFraction: 0.72)

    static let specularGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.24),
            Color.white.opacity(0.08),
            Color.white.opacity(0.02)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let subtleBorder = Color.white.opacity(0.12)
    static let surfaceBackground = Color(NSColor.controlBackgroundColor).opacity(0.6)
}

// MARK: - Tactile Button Style

struct TactileButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(DesignTokens.quickSpring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TactileButtonStyle {
    static var tactile: TactileButtonStyle { TactileButtonStyle() }
    static func tactile(isProminent: Bool = false, cornerRadius: CGFloat = 8) -> TactileButtonStyle {
        TactileButtonStyle(isProminent: isProminent, cornerRadius: cornerRadius)
    }
}

// MARK: - Interactive Row / Card Hover Style

struct InteractiveCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 8
    var isSelected: Bool = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : (isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.4)
                            : (isHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.06)),
                        lineWidth: 1
                    )
            }
            .onHover { hovering in
                withAnimation(DesignTokens.quickSpring) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func interactiveCard(cornerRadius: CGFloat = 8, isSelected: Bool = false) -> some View {
        modifier(InteractiveCardModifier(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}

// MARK: - Glassmorphic Panel Style

struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 14
    var isProminent: Bool = false

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isProminent ? 0.32 : 0.20),
                                Color.white.opacity(isProminent ? 0.12 : 0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 14, isProminent: Bool = false) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, isProminent: isProminent))
    }
}

// MARK: - Micro Status Badges

struct StatusBadge: View {
    let title: String
    var systemImage: String? = nil
    var color: Color = .accentColor
    var isSubtle: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .foregroundStyle(color)
        .background(color.opacity(isSubtle ? 0.10 : 0.18), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(isSubtle ? 0.20 : 0.35), lineWidth: 0.75)
        )
    }
}

// MARK: - Clean Metric Card

struct MetricCounterCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tintColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tintColor)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        )
    }
}
