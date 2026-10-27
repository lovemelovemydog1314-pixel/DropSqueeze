import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab = 0
    @State private var selectedComparison: HistoryItem?
    @State private var isShowingSavingsCard = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerSection
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Segmented Tab Picker
            Picker("页面", selection: $selectedTab) {
                Text("概览").tag(0)
                Text("设置").tag(1)
            }
            .pickerStyle(.segmented)
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
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("DropSqueeze")
                        .font(.system(size: 14, weight: .bold))
                    if model.purchaseManager.isPro {
                        StatusBadge(title: "PRO", systemImage: "sparkles", color: .accentColor)
                    }
                }
                Text(model.purchaseManager.isPro ? "极速静默媒体压缩" : "每日免费额度生效中")
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
                        Text("升级 Pro")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
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
                Text("正在静默压缩…")
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
                .fill(Color.green)
                .frame(width: 7, height: 7)
                .shadow(color: Color.green.opacity(0.4), radius: 3)

            Text(model.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            if model.canUndoClipboardCompression {
                Button("撤销剪贴板") {
                    model.undoClipboardCompression()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Metric Dashboard

    private var metricDashboard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricCounterCard(
                    title: "今日已压缩",
                    value: "\(model.todayCompressionCount) 项",
                    subtitle: model.purchaseManager.isPro ? "无限处理" : "剩余充足",
                    icon: "arrow.down.circle"
                )

                MetricCounterCard(
                    title: "累计节省空间",
                    value: model.formattedSize(model.totalSavedBytes),
                    subtitle: "本周省 \(model.formattedSize(model.weeklySavedBytes))",
                    icon: "sparkles",
                    tintColor: .accentColor
                )
            }

            // Achievement Report Action & Free Quota info
            HStack {
                if !model.purchaseManager.isPro {
                    Text("自动额度：图 \(model.automaticImageCountToday)/15 · 视 \(model.automaticVideoCountToday)/3")
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
                        Text("成就战报")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.tactile)
                .help("查看并导出可视化省流成就卡片")
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
                    Text(model.isDropZoneVisible ? "隐藏压缩舱" : "屏幕边缘压缩舱")
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
        }
    }

    // MARK: - Watched Folder Card

    private var watchedFolderCard: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 26, height: 26)
                Image(systemName: model.isWatchingFolder ? "folder.badge.eye" : "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(model.isWatchingFolder ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.isWatchingFolder ? "文件夹自动监控中" : "文件夹监控已暂停")
                    .font(.system(size: 11, weight: .semibold))
                if let path = model.watchedFolderPath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("在设置中选择自动监控的截图文件夹")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button("配置") {
                selectedTab = 1
            }
            .buttonStyle(.tactile)
            .font(.system(size: 10, weight: .medium))
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75)
        )
    }

    // MARK: - Batch Queue Section

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("批处理队列 · \(model.queueJobs.filter { $0.state == .queued || $0.state == .processing }.count) 待处理")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isManualQueueRunning {
                    Button(model.isManualQueuePaused ? "继续" : "暂停") {
                        model.isManualQueuePaused ? model.resumeManualQueue() : model.pauseManualQueue()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))

                    Button("停止") { model.stopManualQueue() }
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
                            .help("从队列移除")
                        } else if job.state == .skipped || job.state == .cancelled {
                            Button {
                                model.retryQueueJob(job.id)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("重试此文件")
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
                Text("最近压缩")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("保留最近 10 项")
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
                Text("格式转换")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("−\(model.formattedSize(item.savedBytes))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }

            // Quick Menu
            if item.outputPath != nil {
                Menu {
                    Button("打开压缩结果") { model.openOutput(for: item) }
                    Button("在 Finder 中显示") { model.revealOutput(for: item) }
                    if item.sourcePath != nil {
                        Button("对比原件与结果") { selectedComparison = item }
                    }
                    if item.kind == .imageFile, let path = item.outputPath {
                        Button("识别并拷贝文字 (OCR)") {
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
            Text("DropSqueeze v1.2")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 3) {
                    Text("退出")
                    Text("⌘Q")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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
