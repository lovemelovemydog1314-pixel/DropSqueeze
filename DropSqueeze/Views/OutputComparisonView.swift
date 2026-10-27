import AVKit
import AppKit
import PDFKit
import SwiftUI

enum ImageComparisonMode: String, CaseIterable, Identifiable {
    case split = "卷帘对比"
    case sideBySide = "并排对比"

    var id: String { rawValue }
}

struct OutputComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let item: HistoryItem

    @State private var comparisonMode: ImageComparisonMode = .split
    @State private var sourceImage: NSImage?
    @State private var outputImage: NSImage?
    @State private var sourcePlayer: AVPlayer?
    @State private var outputPlayer: AVPlayer?
    @State private var sourcePDF: PDFDocument?
    @State private var outputPDF: PDFDocument?
    @State private var scopedURLs: [URL] = []

    private var isVideo: Bool { item.kind == .videoFile }
    private var isPDF: Bool { item.kind == .pdfFile }
    private var isImage: Bool { item.kind == .imageFile }

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
                if isImage && sourceImage != nil && outputImage != nil {
                    Picker("模式", selection: $comparisonMode) {
                        ForEach(ImageComparisonMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
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

            if isImage && comparisonMode == .split, let sourceImage, let outputImage {
                SplitImageView(
                    sourceImage: sourceImage,
                    outputImage: outputImage,
                    originalBytes: item.originalBytes,
                    resultBytes: item.resultBytes,
                    sourceDetails: item.sourceDetails?.summary,
                    outputDetails: item.outputDetails?.summary
                )
            } else {
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

struct SplitImageView: View {
    let sourceImage: NSImage
    let outputImage: NSImage
    let originalBytes: Int64
    let resultBytes: Int64
    let sourceDetails: String?
    let outputDetails: String?

    @State private var sliderFraction: CGFloat = 0.5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let dividerX = max(10, min(width - 10, width * sliderFraction))

            ZStack(alignment: .leading) {
                // Background layer: Output (compressed image)
                Image(nsImage: outputImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)

                // Foreground layer: Source (original image), clipped to the left of divider
                Image(nsImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle()
                                .frame(width: dividerX, height: height)
                            Spacer(minLength: 0)
                        }
                    )

                // Divider line
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(x: dividerX, y: height / 2)

                // Draggable handle
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                    .overlay(
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4)
                    .position(x: dividerX, y: height / 2)

                // Header Badges
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("原件 · \(ByteCountFormatter.string(fromByteCount: originalBytes, countStyle: .file))")
                                .font(.caption.weight(.semibold))
                            if let sourceDetails, !sourceDetails.isEmpty {
                                Text(sourceDetails)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(12)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("压缩后 · \(ByteCountFormatter.string(fromByteCount: resultBytes, countStyle: .file))")
                                .font(.caption.weight(.semibold))
                            if let outputDetails, !outputDetails.isEmpty {
                                Text(outputDetails)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(12)
                    }

                    Spacer()

                    Text("左右拖拽滑块对比画质细节 · 双击滑块复位")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = value.location.x / width
                        sliderFraction = max(0.02, min(0.98, fraction))
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sliderFraction = 0.5
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
