import AVKit
import AppKit
import PDFKit
import SwiftUI

struct OutputComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let item: HistoryItem

    @State private var sourceImage: NSImage?
    @State private var outputImage: NSImage?
    @State private var sourcePlayer: AVPlayer?
    @State private var outputPlayer: AVPlayer?
    @State private var sourcePDF: PDFDocument?
    @State private var outputPDF: PDFDocument?
    @State private var scopedURLs: [URL] = []

    private var isVideo: Bool { item.kind == .videoFile }
    private var isPDF: Bool { item.kind == .pdfFile }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("压缩前后对比")
                        .font(.title3.weight(.semibold))
                    Text(item.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if item.kind == .imageFile && item.resultBytes >= item.originalBytes {
                    Text(item.resultBytes == item.originalBytes
                         ? "格式转换 · 体积不变"
                         : "格式转换 · 增加 \(ByteCountFormatter.string(fromByteCount: item.resultBytes - item.originalBytes, countStyle: .file))")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("节省 \(ByteCountFormatter.string(fromByteCount: item.savedBytes, countStyle: .file))")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 14) {
                comparisonPanel(
                    title: "原件",
                    size: item.originalBytes,
                    details: item.sourceDetails?.summary,
                    image: sourceImage,
                    player: sourcePlayer,
                    pdf: sourcePDF
                )
                comparisonPanel(
                    title: "压缩结果",
                    size: item.resultBytes,
                    details: item.outputDetails?.summary,
                    image: outputImage,
                    player: outputPlayer,
                    pdf: outputPDF
                )
            }
            if isVideo {
                Text("视频预览默认静音；两侧可分别播放和拖动进度。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(width: 820, height: 500)
        .onAppear(perform: loadPreviews)
        .onDisappear(perform: releaseAccess)
    }

    @ViewBuilder
    private func comparisonPanel(
        title: String,
        size: Int64,
        details: String?,
        image: NSImage?,
        player: AVPlayer?,
        pdf: PDFDocument?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let details, !details.isEmpty {
                        Text(details)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else if let pdf {
                    PDFDocumentPreview(document: pdf)
                } else if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                        Text("无法预览")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadPreviews() {
        guard let sourceURL = item.resolvedSourceURL,
              let outputURL = item.resolvedOutputURL else { return }
        for url in [sourceURL, outputURL] where url.startAccessingSecurityScopedResource() {
            scopedURLs.append(url)
        }

        if isVideo {
            let source = AVPlayer(url: sourceURL)
            let output = AVPlayer(url: outputURL)
            source.isMuted = true
            output.isMuted = true
            sourcePlayer = source
            outputPlayer = output
        } else if isPDF {
            sourcePDF = PDFDocument(url: sourceURL)
            outputPDF = PDFDocument(url: outputURL)
        } else {
            sourceImage = NSImage(contentsOf: sourceURL)
            outputImage = NSImage(contentsOf: outputURL)
        }
    }

    private func releaseAccess() {
        sourcePlayer?.pause()
        outputPlayer?.pause()
        for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
        scopedURLs.removeAll()
        sourcePlayer = nil
        outputPlayer = nil
        sourcePDF = nil
        outputPDF = nil
        sourceImage = nil
        outputImage = nil
    }
}

private struct PDFDocumentPreview: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysAsBook = false
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        view.autoScales = true
    }
}
