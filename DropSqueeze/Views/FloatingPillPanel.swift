import AppKit
import SwiftUI

@MainActor
final class FloatingPillPanelController {
    private let panel: NSPanel
    private let model: AppModel
    private var dismissTimer: Timer?

    init(model: AppModel) {
        self.model = model
        let size = NSSize(width: 340, height: 56)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let view = FloatingPillView(model: model) { [weak self] in
            self?.dismiss()
        }
        panel.contentView = NSHostingView(rootView: view)

        model.showFloatingPillHandler = { [weak self] in
            self?.show()
        }
    }

    func show() {
        dismissTimer?.invalidate()
        positionPanel()
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 1.0
        }

        // Auto-dismiss after 4.5 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.maxY - panel.frame.height - 10
        ))
    }
}

struct FloatingPillView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var l10n = LocalizationManager.shared
    let onClose: () -> Void
    @State private var copiedTextNotice = false

    var body: some View {
        HStack(spacing: 10) {
            // Drag source or status icon
            if let url = model.latestOutputURL {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 1)

                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .contentShape(Circle())
                .onDrag { NSItemProvider(object: url as NSURL) }
                .help(L10n.tr("按住直接拖放"))
            } else {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.green)
                }
            }

            // Description Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(L10n.tr("压缩完成"))
                        .font(.system(size: 11, weight: .bold))

                    if let item = model.history.first {
                        Text("−\(model.formattedSize(item.savedBytes))")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.5)
                            )
                    }
                }

                if let outputURL = model.latestOutputURL {
                    Text(L10n.tr("直接拖拽放入微信/邮件 · %@", outputURL.lastPathComponent))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(L10n.tr("已替换剪贴板 · 按 ⌘V 立即粘贴"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // OCR button if text was recognized
            if let recognizedText = model.latestRecognizedText, !recognizedText.isEmpty {
                Button {
                    model.copyLatestRecognizedText()
                    withAnimation(DesignTokens.quickSpring) {
                        copiedTextNotice = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(DesignTokens.quickSpring) {
                            copiedTextNotice = false
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copiedTextNotice ? "checkmark" : "text.viewfinder")
                            .font(.system(size: 9, weight: .bold))
                        Text(copiedTextNotice ? L10n.tr("已拷贝") : L10n.tr("提取文字"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.75)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.tactile)
                .help(L10n.tr("一键复制截图中识别到的纯文本"))
            }

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.tactile)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
}
