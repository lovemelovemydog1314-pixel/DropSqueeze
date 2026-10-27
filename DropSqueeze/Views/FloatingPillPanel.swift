import AppKit
import SwiftUI

@MainActor
final class FloatingPillPanelController {
    private let panel: NSPanel
    private let model: AppModel
    private var dismissTimer: Timer?

    init(model: AppModel) {
        self.model = model
        let size = NSSize(width: 320, height: 52)
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
            context.duration = 0.2
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
            context.duration = 0.25
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

private struct FloatingPillView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    @State private var copiedTextNotice = false

    var body: some View {
        HStack(spacing: 9) {
            // Drag source or status icon
            if let url = model.latestOutputURL {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.16), in: Circle())
                    .contentShape(Circle())
                    .onDrag { NSItemProvider(object: url as NSURL) }
                    .help("按住此图标直接拖出压缩文件")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("压缩完成")
                        .font(.system(size: 11, weight: .bold))
                    if let item = model.history.first {
                        Text("−\(model.formattedSize(item.savedBytes))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let outputURL = model.latestOutputURL {
                    Text("可直接拖出 · \(outputURL.lastPathComponent)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("已替换剪贴板 · Cmd+V 粘贴")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // OCR button if text was recognized
            if let recognizedText = model.latestRecognizedText, !recognizedText.isEmpty {
                Button {
                    model.copyLatestRecognizedText()
                    copiedTextNotice = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedTextNotice = false
                    }
                } label: {
                    Text(copiedTextNotice ? "已拷贝✓" : "拷贝文字")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("一键复制截图中识别到的纯文本")
            }

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
