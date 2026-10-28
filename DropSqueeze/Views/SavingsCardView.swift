import AppKit
import SwiftUI

struct SavingsCardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject var model: AppModel
    @State private var copySuccessNotice = false

    var body: some View {
        VStack(spacing: 16) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.tr("省流战报与成就"))
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
                Button(L10n.tr("完成")) { dismiss() }
                    .buttonStyle(.tactile)
                    .keyboardShortcut(.defaultAction)
            }

            // Card Graphic Preview
            SavingsCardGraphic(model: model)
                .frame(width: 400, height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 16, y: 8)

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    copyCardImage()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copySuccessNotice ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .bold))
                        Text(copySuccessNotice ? L10n.tr("已拷贝到剪贴板✓") : L10n.tr("拷贝战报卡片"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.tactile)

                Button {
                    saveCardImage()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .bold))
                        Text(L10n.tr("保存高清图片"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.tactile)
            }
        }
        .padding(20)
        .frame(width: 440, height: 390)
    }

    private func renderCardImage() -> NSImage? {
        let graphic = SavingsCardGraphic(model: model)
            .frame(width: 500, height: 325)
        let renderer = ImageRenderer(content: graphic)
        renderer.scale = 2.0
        return renderer.nsImage
    }

    private func copyCardImage() {
        guard let image = renderCardImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        withAnimation(DesignTokens.quickSpring) {
            copySuccessNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(DesignTokens.quickSpring) {
                copySuccessNotice = false
            }
        }
    }

    private func saveCardImage() {
        guard let image = renderCardImage(),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let destinationURL = picturesURL.appendingPathComponent("DropSqueeze-Savings-\(Int(Date().timeIntervalSince1970)).png")
        try? pngData.write(to: destinationURL)
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }
}

struct SavingsCardGraphic: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            // Dark Titanium Base
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.04, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Radiant Ambient Glows
            Circle()
                .fill(Color.accentColor.opacity(0.24))
                .blur(radius: 60)
                .offset(x: -120, y: -70)

            Circle()
                .fill(Color.purple.opacity(0.14))
                .blur(radius: 70)
                .offset(x: 140, y: 80)

            VStack(alignment: .leading, spacing: 14) {
                // Brand Header
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: 24, height: 24)
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text("DropSqueeze")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text(L10n.tr("省流战报"))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.22), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 0.75)
                    )
                    .foregroundStyle(Color.accentColor)
                }

                // Giant Hero Stats
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("累计已为你省下"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    Text(model.formattedSize(model.totalSavedBytes))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 0.85, green: 0.92, blue: 1.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                // 3-Column Metrics Grid
                HStack(spacing: 10) {
                    metricBlock(
                        title: L10n.tr("总处理项"),
                        value: "\(model.totalCompressionCount) \(L10n.tr("items_unit"))",
                        icon: "square.stack.3d.down.right.fill"
                    )
                    metricBlock(
                        title: L10n.tr("本周节省"),
                        value: model.formattedSize(model.weeklySavedBytes),
                        icon: "bolt.fill"
                    )
                    metricBlock(
                        title: L10n.tr("释放原图约"),
                        value: L10n.tr("约 %d 张", max(1, model.totalSavedBytes / 5_000_000)),
                        icon: "photo.stack.fill"
                    )
                }

                Spacer(minLength: 0)

                // Footer Guarantee
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 9))
                        Text(L10n.tr("100% 本地运算 · 零云端隐私泄露"))
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.55))

                    Spacer()

                    Text(L10n.tr("macOS 极速静默媒体压缩"))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func metricBlock(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.45))
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        )
    }
}
