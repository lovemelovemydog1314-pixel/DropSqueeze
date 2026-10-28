import AppKit
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var selectedTab = 0
    @State private var selectedComparison: HistoryItem?
    @State private var isShowingSavingsCard = false
    @State private var isShowingVideoQuickEdit = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerSection
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Segmented Tab Picker
            Picker("", selection: $selectedTab) {
                Text(L10n.tr("概览")).tag(0)
                Text(L10n.tr("设置")).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Divider()
                .opacity(0.4)

            // Content Area
            if selectedTab == 0 {
                overviewContent
            } else {
                SettingsView(model: model, settings: model.settings, purchaseManager: model.purchaseManager)
            }
        }
        .frame(width: 380, height: 580)
        .sheet(item: $selectedComparison) { item in
            OutputComparisonView(item: item)
        }
        .sheet(isPresented: $isShowingSavingsCard) {
            SavingsCardView(model: model)
        }
        .sheet(isPresented: $isShowingVideoQuickEdit) {
            VideoQuickEditView(model: model)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 10) {
            AppBrandIcon(size: 30)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("DropSqueeze")
                        .font(.system(size: 14, weight: .bold))
                    if model.purchaseManager.isPro {
                        StatusBadge(title: "PRO", systemImage: "sparkles", color: .accentColor)
                    }
                }
                Text(model.purchaseManager.isPro ? L10n.tr("极速静默媒体压缩") : L10n.tr("每日免费额度生效中"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !model.purchaseManager.isPro {
                Button {
                    model.requestPro(for: .general)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.tr("升级 Pro"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color(red: 0.10, green: 0.44, blue: 0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.75)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 3, y: 1)
                }
                .buttonStyle(.tactile)
            }
        }
    }

    // MARK: - Overview Content

    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Live Status / Ongoing Task Card
                if model.isProcessing || model.currentFileName != nil {
                    activeProcessingCard
                } else {
                    idleStatusCard
                }

                // Metric Hero Stats
                metricDashboard

                // Floating Notch / Drop Zone & Quick Actions
                quickActionControls

                clipboardCollectionSection

                // Monitored Folder Status
                watchedFolderCard

                // Batch Queue (if any)
                if !model.queueJobs.isEmpty {
                    queueSection
                }

                // Recent Compression History
                if !model.history.isEmpty {
                    recentHistorySection
                }

                Spacer(minLength: 4)

                // Footer Quit Bar
                footerSection
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Active Processing Card

    private var activeProcessingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.tr("正在静默压缩…"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let progress = model.currentProgress {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .monospacedDigit()
                }
            }

            if let currentFileName = model.currentFileName {
                Text(currentFileName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let progress = model.currentProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Idle Status Card

    private var idleStatusCard: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.22, green: 0.82, blue: 0.46))
                .frame(width: 7, height: 7)
                .shadow(color: Color.green.opacity(0.4), radius: 3)

            Text(L10n.tr(model.statusMessage))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            if model.canUndoClipboardCompression {
                Button(L10n.tr("撤销剪贴板")) {
                    model.undoClipboardCompression()
                }
                .buttonStyle(.tactile)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
        )
    }

    // MARK: - Metric Dashboard

    private var metricDashboard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricCounterCard(
                    title: L10n.tr("今日已压缩"),
                    value: "\(model.todayCompressionCount) \(L10n.tr("items_unit"))",
                    subtitle: model.purchaseManager.isPro ? L10n.tr("无限处理") : L10n.tr("剩余充足"),
                    icon: "arrow.down.circle"
                )

                MetricCounterCard(
                    title: L10n.tr("累计节省空间"),
                    value: model.formattedSize(model.totalSavedBytes),
                    subtitle: L10n.tr("本周省 %@", model.formattedSize(model.weeklySavedBytes)),
                    icon: "sparkles",
                    tintColor: .accentColor
                )
            }

            // Achievement Report Action & Free Quota info
            HStack {
                if !model.purchaseManager.isPro {
                    Text(L10n.tr("自动额度：图 %d/15 · 视 %d/3", model.automaticImageCountToday, model.automaticVideoCountToday))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    isShowingSavingsCard = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L10n.tr("成就战报"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.tactile)
                .help(L10n.tr("查看并导出可视化省流成就卡片"))
            }
        }
    }

    // MARK: - Quick Action Controls

    private var quickActionControls: some View {
        HStack(spacing: 8) {
            // DropZone toggle button
            Button {
                model.toggleDropZone()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.isDropZoneVisible ? "eye.slash.fill" : "hand.draw.fill")
                        .font(.system(size: 11))
                    Text(model.isDropZoneVisible ? L10n.tr("隐藏压缩舱") : L10n.tr("屏幕边缘压缩舱"))
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Circle()
                        .fill(model.isDropZoneVisible ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(model.isDropZoneVisible ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.tactile)

            Button {
                isShowingVideoQuickEdit = true
            } label: {
                Label(L10n.tr("视频轻编辑"), systemImage: "scissors")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.tactile)
            .help(L10n.tr("剪辑片段、导出 GIF 或提取音频"))
        }
    }

    private var clipboardCollectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("剪贴板收集栏"))
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.tr("本次会话内存暂存 · 最多 %d 项，单图 10 MB", ClipboardCollectionBuffer.maximumItemCount))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle(L10n.tr("收集"), isOn: Binding(
                    get: { model.settings.clipboardCollectionEnabled },
                    set: { model.setClipboardCollectionEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
            }

            if model.settings.clipboardCollectionEnabled && model.clipboardCollectionItems.isEmpty {
                Label(L10n.tr("开启后，复制图片或 Finder 文件即可加入"), systemImage: "doc.on.clipboard")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else if !model.clipboardCollectionItems.isEmpty {
                HStack {
                    Text("\(model.clipboardCollectionItems.count) / \(ClipboardCollectionBuffer.maximumItemCount) \(L10n.tr("items_unit"))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.tr("清空")) { model.clearClipboardCollection() }
                        .buttonStyle(.link)
                        .font(.system(size: 9))
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(model.clipboardCollectionItems) { item in
                            ClipboardCollectionItemCard(
                                item: item,
                                onCopy: { model.copyClipboardCollectionItem(item) },
                                onRemove: { model.removeClipboardCollectionItem(item) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(height: 132)
            } else {
                Text(L10n.tr("收集已关闭；当前收集项会保留到退出应用或手动清空。"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
        )
    }

    // MARK: - Watched Folder Card

    private var watchedFolderCard: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(model.isWatchingFolder ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.06))
                    .frame(width: 26, height: 26)
                Image(systemName: model.isWatchingFolder ? "folder.badge.gearshape" : "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(model.isWatchingFolder ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.isWatchingFolder ? L10n.tr("文件夹自动监控中") : L10n.tr("文件夹监控已暂停"))
                    .font(.system(size: 11, weight: .semibold))
                if let path = model.watchedFolderPath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(L10n.tr("在设置中选择自动监控的截图文件夹"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button(L10n.tr("配置")) {
                selectedTab = 1
            }
            .buttonStyle(.tactile)
            .font(.system(size: 10, weight: .medium))
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .interactiveCard(cornerRadius: 8)
    }

    // MARK: - Batch Queue Section

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.tr("批处理队列 · %d 待处理", model.queueJobs.filter { $0.state == .queued || $0.state == .processing }.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isManualQueueRunning {
                    Button(model.isManualQueuePaused ? L10n.tr("继续") : L10n.tr("暂停")) {
                        model.isManualQueuePaused ? model.resumeManualQueue() : model.pauseManualQueue()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))

                    Button(L10n.tr("停止")) { model.stopManualQueue() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                }
            }

            VStack(spacing: 4) {
                ForEach(model.queueJobs) { job in
                    HStack(spacing: 6) {
                        if job.state == .processing {
                            if let progress = job.progress {
                                ProgressView(value: progress).frame(width: 32)
                            } else {
                                ProgressView().controlSize(.mini)
                            }
                        } else {
                            Image(systemName: job.state == .completed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10))
                                .foregroundStyle(job.state == .completed ? Color.green : Color.secondary)
                        }
                        Text(job.url.lastPathComponent)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(job.state.title)
                            .foregroundStyle(.tertiary)
                            .help(job.detail ?? "")
                        Menu {
                            Button("使用当前设置") {
                                model.setQueueJobProfile(job.id, identifier: CompressionProfileReference.currentIdentifier)
                            }
                            Divider()
                            ForEach(CompressionScenario.allCases) { scenario in
                                Button(scenario.title) {
                                    model.setQueueJobProfile(
                                        job.id,
                                        identifier: CompressionProfileReference.identifier(for: scenario)
                                    )
                                }
                            }
                            if !model.settings.savedProfiles.isEmpty {
                                Divider()
                                ForEach(model.settings.savedProfiles) { profile in
                                    Button(profile.name) {
                                        model.setQueueJobProfile(
                                            job.id,
                                            identifier: CompressionProfileReference.identifier(for: profile)
                                        )
                                    }
                                }
                            }
                        } label: {
                            Label(job.profileOverride?.name ?? "当前设置", systemImage: "slider.horizontal.3")
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(job.state != .queued)
                        .help(job.state == .queued ? "为此文件选择单独的压缩配置" : "此文件使用：\(job.profileOverride?.name ?? "当前设置")")
                        if job.state == .queued {
                            Button {
                                model.removeQueuedJob(job.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.tr("从队列移除"))
                        } else if job.state == .skipped || job.state == .cancelled {
                            Button {
                                model.retryQueueJob(job.id)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.tr("重试此文件"))
                        }
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Recent History Section

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.tr("最近压缩"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.tr("保留最近 10 项"))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 5) {
                ForEach(model.history.prefix(10)) { item in
                    historyRow(for: item)
                }
            }
        }
    }

    private func historyRow(for item: HistoryItem) -> some View {
        HStack(spacing: 8) {
            // Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(iconBackgroundColor(for: item.kind))
                    .frame(width: 22, height: 22)
                Image(systemName: icon(for: item.kind))
                    .font(.system(size: 10))
                    .foregroundStyle(iconForegroundColor(for: item.kind))
            }

            // Name
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text("\(model.formattedSize(item.originalBytes)) → \(model.formattedSize(item.resultBytes))")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            // Saved Badge
            if item.kind == .imageFile && item.resultBytes >= item.originalBytes {
                Text(L10n.tr("格式转换"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.06), in: Capsule())
            } else {
                Text("−\(model.formattedSize(item.savedBytes))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 0.5)
                    )
            }

            // Quick Menu
            if item.outputPath != nil {
                Menu {
                    Button(L10n.tr("打开压缩结果")) { model.openOutput(for: item) }
                    Button(L10n.tr("在 Finder 中显示")) { model.revealOutput(for: item) }
                    if item.sourcePath != nil {
                        Button(L10n.tr("对比原件与结果")) { selectedComparison = item }
                    }
                    if item.kind == .imageFile, let path = item.outputPath {
                        Button(L10n.tr("识别并拷贝文字 (OCR)")) {
                            Task {
                                let text = await VisionTextExtractor.shared.extractText(from: URL(fileURLWithPath: path))
                                if let text, !text.isEmpty {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .interactiveCard(cornerRadius: 7)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: 4, height: 4)
                Text("DropSqueeze v1.2")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.tr("退出"))
                    Text("⌘Q")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.tactile)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func icon(for kind: HistoryItem.Kind) -> String {
        switch kind {
        case .clipboardImage: return "doc.on.clipboard"
        case .imageFile: return "photo"
        case .videoFile: return "film"
        case .pdfFile: return "doc.text"
        }
    }

    private func iconBackgroundColor(for kind: HistoryItem.Kind) -> Color {
        switch kind {
        case .clipboardImage: return Color.blue.opacity(0.15)
        case .imageFile: return Color.purple.opacity(0.15)
        case .videoFile: return Color.orange.opacity(0.15)
        case .pdfFile: return Color.red.opacity(0.15)
        }
    }

    private func iconForegroundColor(for kind: HistoryItem.Kind) -> Color {
        switch kind {
        case .clipboardImage: return Color.blue
        case .imageFile: return Color.purple
        case .videoFile: return Color.orange
        case .pdfFile: return Color.red
        }
    }
}

private enum VideoQuickEditAction: String, CaseIterable, Identifiable {
    case compressClip
    case gif
    case audio

    var id: String { rawValue }
    var title: String {
        switch self {
        case .compressClip: return "压缩所选片段"
        case .gif: return "导出 GIF"
        case .audio: return "提取 M4A 音频"
        }
    }
}

private struct VideoQuickEditView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL: URL?
    @State private var sourceAccessActive = false
    @State private var player: AVPlayer?
    @State private var durationSeconds = 0.0
    @State private var startSeconds = 0.0
    @State private var endSeconds = 0.0
    @State private var action: VideoQuickEditAction = .compressClip
    @State private var gifFramesPerSecond = 15
    @State private var gifMaximumDimension = 720
    @State private var selectedOutputDirectory: URL?
    @State private var outputDirectoryAccessActive = false
    @State private var isProcessing = false
    @State private var progress = 0.0
    @State private var resultURL: URL?
    @State private var errorMessage: String?
    @State private var cancellation = VideoTranscoderCancellation()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("视频轻编辑")
                        .font(.system(size: 17, weight: .semibold))
                    Text("选择片段后压缩、转 GIF 或提取音频。原视频会完整保留。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if let player {
                VideoPlayer(player: player)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("选择一个视频")
                        .font(.system(size: 13, weight: .semibold))
                    Text("支持常见的 MOV、MP4 视频文件")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 10) {
                Button {
                    chooseVideo()
                } label: {
                    Label(sourceURL == nil ? "选择视频" : "更换视频", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                if let sourceURL {
                    Text(sourceURL.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            if durationSeconds >= VideoTrimRange.minimumDuration {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("片段范围")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(timeLabel(startSeconds)) – \(timeLabel(endSeconds)) · 共 \(timeLabel(endSeconds - startSeconds))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text("开始").font(.system(size: 10)).foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { startSeconds },
                                set: { startSeconds = min($0, max(0, endSeconds - VideoTrimRange.minimumDuration)) }
                            ),
                            in: 0...max(0, durationSeconds - VideoTrimRange.minimumDuration)
                        )
                        Text(timeLabel(startSeconds)).font(.system(size: 10, design: .monospaced)).frame(width: 46, alignment: .trailing)
                    }
                    HStack(spacing: 8) {
                        Text("结束").font(.system(size: 10)).foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { endSeconds },
                                set: { endSeconds = max($0, startSeconds + VideoTrimRange.minimumDuration) }
                            ),
                            in: min(durationSeconds, startSeconds + VideoTrimRange.minimumDuration)...durationSeconds
                        )
                        Text(timeLabel(endSeconds)).font(.system(size: 10, design: .monospaced)).frame(width: 46, alignment: .trailing)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            HStack(spacing: 12) {
                Picker("处理方式", selection: $action) {
                    ForEach(VideoQuickEditAction.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                if action == .gif {
                    Picker("帧率", selection: $gifFramesPerSecond) {
                        ForEach([12, 15, 24, 30], id: \.self) { Text("\($0) fps").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 100)

                    Picker("长边", selection: $gifMaximumDimension) {
                        ForEach([480, 720, 960, 1280], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(outputLocationDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("更改") { chooseOutputDirectory() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }

            if isProcessing {
                HStack(spacing: 8) {
                    if action == .compressClip {
                        ProgressView(value: progress)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 38, alignment: .trailing)
                    } else {
                        ProgressView()
                        Text("正在导出…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Button("取消") { cancellation.cancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let resultURL {
                HStack(spacing: 8) {
                    Label("已导出：\(resultURL.lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    Spacer()
                    Button("打开") { NSWorkspace.shared.open(resultURL) }
                    Button("显示") { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
                }
            }

            HStack {
                Text(actionDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                Spacer()
                Button {
                    Task { await processSelection() }
                } label: {
                    Label(isProcessing ? "处理中" : action.title, systemImage: action == .audio ? "waveform" : (action == .gif ? "gift" : "scissors"))
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourceURL == nil || durationSeconds < VideoTrimRange.minimumDuration || isProcessing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 650, height: 650)
        .onDisappear {
            if isProcessing { cancellation.cancel() }
            player?.pause()
            if sourceAccessActive { sourceURL?.stopAccessingSecurityScopedResource() }
            if outputDirectoryAccessActive { selectedOutputDirectory?.stopAccessingSecurityScopedResource() }
        }
    }

    private var outputLocationDescription: String {
        selectedOutputDirectory?.lastPathComponent
            ?? model.outputFolderURL?.lastPathComponent
            ?? sourceURL?.deletingLastPathComponent().lastPathComponent
            ?? "原文件所在文件夹"
    }

    private var actionDetail: String {
        switch action {
        case .compressClip: return "按应用的视频压缩设置导出片段；长度约束仍会生效。"
        case .gif: return "GIF 片段最长 15 秒，帧率和长边可调整。"
        case .audio: return "仅提取所选范围内的音轨，保存为通用 M4A。"
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.title = "选择要编辑的视频"
        panel.prompt = "选择视频"
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        player?.pause()
        if sourceAccessActive { sourceURL?.stopAccessingSecurityScopedResource() }
        sourceAccessActive = url.startAccessingSecurityScopedResource()
        sourceURL = url
        resultURL = nil
        errorMessage = nil
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration).seconds
                guard duration.isFinite, duration >= VideoTrimRange.minimumDuration else {
                    throw VideoTrimRangeError.invalidRange
                }
                durationSeconds = duration
                startSeconds = 0
                endSeconds = duration
                let nextPlayer = AVPlayer(url: url)
                player = nextPlayer
                nextPlayer.play()
            } catch {
                player = nil
                durationSeconds = 0
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择轻编辑结果的保存文件夹"
        panel.prompt = "保存到此文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedOutputDirectory ?? model.outputFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if outputDirectoryAccessActive { selectedOutputDirectory?.stopAccessingSecurityScopedResource() }
        selectedOutputDirectory = url
        outputDirectoryAccessActive = url.startAccessingSecurityScopedResource()
    }

    @MainActor
    private func processSelection() async {
        guard let sourceURL else { return }
        isProcessing = true
        progress = 0
        resultURL = nil
        errorMessage = nil
        cancellation = VideoTranscoderCancellation()
        defer { isProcessing = false }

        var startedConfiguredOutputAccess = false
        let outputDirectory: URL
        if let selectedOutputDirectory {
            outputDirectory = selectedOutputDirectory
        } else if let configuredOutput = model.outputFolderURL {
            startedConfiguredOutputAccess = configuredOutput.startAccessingSecurityScopedResource()
            outputDirectory = configuredOutput
        } else {
            outputDirectory = sourceURL.deletingLastPathComponent()
        }
        defer {
            if startedConfiguredOutputAccess, let configuredOutput = model.outputFolderURL {
                configuredOutput.stopAccessingSecurityScopedResource()
            }
        }

        do {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  FileManager.default.isWritableFile(atPath: outputDirectory.path) else {
                throw AudioExtractionError.exportFailed("没有写入输出文件夹的权限，请更换文件夹")
            }
            let range = try VideoTrimRange(
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                assetDurationSeconds: durationSeconds
            )
            let exportedURL: URL
            switch action {
            case .compressClip:
                exportedURL = try await VideoTranscoder.transcodeToSmallerMP4(
                    sourceURL,
                    preset: model.settings.videoOutputPreset,
                    codec: model.settings.videoCodecPreference,
                    bitrateTarget: model.settings.videoBitrateTarget,
                    maximumFrameRate: model.settings.videoFrameRate,
                    includesAudio: model.settings.videoIncludesAudio,
                    maximumSizeMB: model.settings.videoMaximumSizeMB,
                    trimRange: range,
                    requiresSmallerOutput: false,
                    outputDirectory: outputDirectory,
                    cancellation: cancellation,
                    onProgress: { value in
                        Task { @MainActor in progress = value }
                    }
                )
            case .gif:
                exportedURL = try await GIFGenerator.generateGIF(
                    from: sourceURL,
                    trimRange: range,
                    framesPerSecond: gifFramesPerSecond,
                    maximumDimension: gifMaximumDimension,
                    requiresSmallerOutput: false,
                    outputSuffix: "edited",
                    cancellation: cancellation,
                    outputDirectory: outputDirectory
                )
            case .audio:
                exportedURL = try await AudioExtractor.extractM4A(
                    from: sourceURL,
                    trimRange: range,
                    cancellation: cancellation,
                    outputDirectory: outputDirectory
                )
            }
            resultURL = exportedURL
            progress = 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        String(format: "%0.2f 秒", seconds)
    }
}

private struct ClipboardCollectionItemCard: View {
    let item: ClipboardCollectionItem
    let onCopy: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                preview
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(item.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("从收集栏移除")
            }

            Text("\(item.detail) · \(item.createdAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onCopy) {
                Label("放回剪贴板", systemImage: "doc.on.clipboard")
                    .font(.system(size: 9, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(7)
        .frame(width: 156, height: 124)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnailData = item.thumbnailData, let image = NSImage(data: thumbnailData) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: item.isImage ? "photo" : "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}
