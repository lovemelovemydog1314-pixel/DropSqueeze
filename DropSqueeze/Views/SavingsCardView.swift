import AppKit
import SwiftUI

struct SavingsCardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    @State private var copySuccessNotice = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("省流战报与成就")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            SavingsCardGraphic(model: model)
                .frame(width: 380, height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)

            HStack(spacing: 12) {
                Button {
                    copyCardImage()
                } label: {
                    Label(copySuccessNotice ? "已拷贝卡片图片✓" : "拷贝战报卡片", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    saveCardImage()
                } label: {
                    Label("保存为图片", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 420, height: 380)
    }

    private func renderCardImage() -> NSImage? {
        let graphic = SavingsCardGraphic(model: model)
            .frame(width: 480, height: 320)
        let renderer = ImageRenderer(content: graphic)
        renderer.scale = 2.0
        return renderer.nsImage
    }

    private func copyCardImage() {
        guard let image = renderCardImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        copySuccessNotice = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            copySuccessNotice = false
        }
    }

    private func saveCardImage() {
        guard let image = renderCardImage(),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let destinationURL = picturesURL.appendingPathComponent("DropSqueeze-Savings-\(Date().timeIntervalSince1970).png")
        try? pngData.write(to: destinationURL)
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }
}

struct SavingsCardGraphic: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.15, blue: 0.22),
                    Color(red: 0.08, green: 0.09, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Decorative background glow
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .blur(radius: 50)
                .offset(x: -80, y: -60)

            VStack(alignment: .leading, spacing: 14) {
                // Header brand
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("DropSqueeze")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("省流战报")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.2), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                // Giant headline stats
                VStack(alignment: .leading, spacing: 2) {
                    Text("已累计节省")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(model.formattedSize(model.totalSavedBytes))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 0.8, green: 0.9, blue: 1.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                // Grid stats
                HStack(spacing: 12) {
                    metricBlock(
                        title: "总处理项",
                        value: "\(model.totalCompressionCount) 项"
                    )
                    metricBlock(
                        title: "本周节省",
                        value: model.formattedSize(model.weeklySavedBytes)
                    )
                    metricBlock(
                        title: "释放原图约",
                        value: "\(max(1, model.totalSavedBytes / 5_000_000)) 张"
                    )
                }

                Spacer(minLength: 0)

                // Footer
                HStack {
                    Label("100% 本地运算 · 零云端上传", systemImage: "lock.shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("macOS 极速静默媒体压缩")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
