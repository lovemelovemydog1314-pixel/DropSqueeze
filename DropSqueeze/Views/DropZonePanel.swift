import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DropZonePanelController {
    private let panel: NSPanel
    private let model: AppModel
    private var globalDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var autoHideWorkItem: DispatchWorkItem?
    private var temporarilyShownForDrag = false
    private var dragInProgress = false
    private var dropCountWhenShown = 0

    init(model: AppModel) {
        self.model = model
        let size = NSSize(width: 340, height: 205)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        let dropZoneView = DropZoneView(model: model) { [weak panel] in
            panel?.orderOut(nil)
            model.setDropZoneVisible(false)
        }
        panel.contentView = NSHostingView(rootView: dropZoneView)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        positionPanel()
        model.showDropZoneHandler = { [weak self] in self?.show() }
        model.hideDropZoneHandler = { [weak self] in self?.hide() }
        model.dropAcceptedHandler = { [weak self] in
            self?.autoHideWorkItem?.cancel()
            self?.temporarilyShownForDrag = false
            self?.dragInProgress = false
        }
        installGlobalDragMonitors()
    }

    func show() {
        autoHideWorkItem?.cancel()
        temporarilyShownForDrag = false
        dragInProgress = false
        panel.orderFrontRegardless()
        model.setDropZoneVisible(true)
    }

    func hide() {
        autoHideWorkItem?.cancel()
        temporarilyShownForDrag = false
        dragInProgress = false
        panel.orderOut(nil)
        model.setDropZoneVisible(false)
    }

    func stop() {
        autoHideWorkItem?.cancel()
        if let globalDragMonitor { NSEvent.removeMonitor(globalDragMonitor) }
        if let globalMouseUpMonitor { NSEvent.removeMonitor(globalMouseUpMonitor) }
        globalDragMonitor = nil
        globalMouseUpMonitor = nil
    }

    private func installGlobalDragMonitors() {
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async { self?.handleGlobalDrag() }
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            DispatchQueue.main.async { self?.handleGlobalMouseUp() }
        }
    }

    private func handleGlobalDrag() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              pointer.y >= screen.visibleFrame.maxY - 150 else { return }
        positionPanel(on: screen)

        if !model.isDropZoneVisible {
            temporarilyShownForDrag = true
            dragInProgress = true
            dropCountWhenShown = model.dropRequestCount
            panel.orderFrontRegardless()
            model.setDropZoneVisible(true)
        } else if temporarilyShownForDrag {
            autoHideWorkItem?.cancel()
            dragInProgress = true
        }
    }

    private func handleGlobalMouseUp() {
        guard temporarilyShownForDrag, dragInProgress else { return }
        dragInProgress = false
        autoHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.temporarilyShownForDrag else { return }
            if self.model.isProcessing || self.model.dropRequestCount != self.dropCountWhenShown {
                self.temporarilyShownForDrag = false
                return
            }
            self.hide()
        }
        autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func positionPanel(on requestedScreen: NSScreen? = nil) {
        guard let screen = requestedScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.maxY - panel.frame.height - 10
        ))
    }
}

private struct DropZoneView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            headerBar
            statusSection
            supportedTypesText
            scenarioAndAudioBar
            if model.isManualQueueRunning {
                queueSection
            }
            if let outputURL = model.latestOutputURL {
                outputSection(for: outputURL)
            }
            if !model.purchaseManager.isPro {
                proBannerSection
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.16), lineWidth: isTargeted ? 2 : 1)
        }
        .scaleEffect(isTargeted ? 1.04 : 1)
        .animation(.easeOut(duration: 0.16), value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: receiveFiles)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DropSqueeze 文件压缩区，拖入图片、GIF、PDF、MOV、MP4 或 M4V")
    }

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 8) {
            if model.isProcessing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(model.isProcessing ? "正在压缩…" : "DropSqueeze")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            if model.canUndoClipboardCompression {
                Button("撤销") { model.undoClipboardCompression() }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("隐藏悬浮压缩舱")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let currentFileName = model.currentFileName {
            HStack(spacing: 6) {
                Text(currentFileName)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if model.queuedFileCount > 0 {
                    Text("+\(model.queuedFileCount) 排队")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let progress = model.currentProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(isTargeted ? "松开以压缩" : model.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var supportedTypesText: some View {
        Text("拖入图片 · GIF · PDF · MOV · MP4 · M4V")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var scenarioAndAudioBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(CompressionScenario.allCases) { scenario in
                    Button("\(scenario.title)\(scenario.requiredProFeature == nil ? "" : " · Pro") · \(scenario.detail)") {
                        model.applyCompressionScenario(scenario)
                    }
                }
                if !model.settings.savedProfiles.isEmpty {
                    Divider()
                    ForEach(model.settings.savedProfiles) { profile in
                        Button("应用：\(profile.name)") { model.applySavedProfile(profile) }
                    }
                }
            } label: {
                Label("预设：\(model.settings.imageResizePreset.title)", systemImage: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)

            Spacer(minLength: 4)

            Button {
                model.settings.setVideoIncludesAudio(!model.settings.videoIncludesAudio)
            } label: {
                Label(
                    model.settings.videoIncludesAudio ? "保留音频" : "录屏静音",
                    systemImage: model.settings.videoIncludesAudio ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(model.settings.videoIncludesAudio ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(model.settings.videoIncludesAudio ? "点击切换为静音/剥离音频" : "已开启录屏静音，点击恢复保留音频")
        }
    }

    @ViewBuilder
    private var queueSection: some View {
        HStack {
            Text(model.isManualQueuePaused ? "队列已暂停" : (model.queuedFileCount > 0 ? "队列中还有 \(model.queuedFileCount) 个文件" : "正在处理最后一个文件"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(model.isManualQueuePaused ? "继续" : "暂停") {
                model.isManualQueuePaused ? model.resumeManualQueue() : model.pauseManualQueue()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            Button("停止队列") { model.stopManualQueue() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
        }
    }

    @ViewBuilder
    private func outputSection(for outputURL: URL) -> some View {
        Label {
            Text("拖出：\(outputURL.lastPathComponent)")
                .lineLimit(1)
        } icon: {
            Image(systemName: "square.and.arrow.up")
        }
        .font(.system(size: 10, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: outputURL as NSURL) }
    }

    @ViewBuilder
    private var proBannerSection: some View {
        Button("解锁 Pro · 本周已省 \(model.formattedSize(model.weeklySavedBytes))") {
            model.requestPro(for: .general)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func receiveFiles(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var loadedURLs = Array<URL?>(repeating: nil, count: fileProviders.count)
        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = Self.fileURL(from: item)
                lock.lock()
                loadedURLs[index] = url
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = loadedURLs.compactMap { $0 }
            guard !urls.isEmpty else { return }
            self.model.processDroppedURLs(urls)
        }
        return true
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
            if let text = String(data: data, encoding: .utf8) { return URL(string: text) }
        }
        if let text = item as? String { return URL(string: text) }
        return nil
    }
}
