import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab = 0
    @State private var selectedComparison: HistoryItem?
    @State private var isShowingSavingsCard = false

    var body: some View {
        VStack(spacing: 10) {
            Picker("页面", selection: $selectedTab) {
                Text("概览").tag(0)
                Text("设置").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedTab == 0 {
                overview
            } else {
                SettingsView(model: model, settings: model.settings, purchaseManager: model.purchaseManager)
            }
        }
        .padding(12)
        .frame(width: 370, height: 570)
        .sheet(item: $selectedComparison) { item in
            OutputComparisonView(item: item)
        }
        .sheet(isPresented: $isShowingSavingsCard) {
            SavingsCardView(model: model)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DropSqueeze").font(.headline)
                Spacer()
                if model.purchaseManager.isPro {
                    Label("Pro", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                } else {
                    Button("升级 Pro") { model.requestPro(for: .general) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let currentFileName = model.currentFileName {
                HStack(spacing: 8) {
                    if let progress = model.currentProgress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(currentFileName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if model.isManualQueueRunning {
                HStack {
                    Text(queueSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(model.isManualQueuePaused ? "继续" : "暂停") {
                        model.isManualQueuePaused ? model.resumeManualQueue() : model.pauseManualQueue()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    Button("停止") { model.stopManualQueue() }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
            }
            if !model.queueJobs.isEmpty {
                DisclosureGroup("批处理队列 · \(model.queueJobs.filter { $0.state == .queued || $0.state == .processing }.count) 个待处理") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(model.queueJobs) { job in
                                HStack(spacing: 6) {
                                    if job.state == .processing {
                                        if let progress = job.progress {
                                            ProgressView(value: progress).frame(width: 34)
                                        } else {
                                            ProgressView().controlSize(.mini)
                                        }
                                    } else {
                                        Image(systemName: job.state == .completed ? "checkmark.circle" : "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(job.url.lastPathComponent)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(job.state.title)
                                        .foregroundStyle(.tertiary)
                                        .help(job.detail ?? "")
                                    if job.state == .queued {
                                        Button {
                                            model.removeQueuedJob(job.id)
                                        } label: {
                                            Image(systemName: "xmark.circle")
                                        }
                                        .buttonStyle(.plain)
                                        .help("从队列移除")
                                    } else if job.state == .skipped || job.state == .cancelled {
                                        Button {
                                            model.retryQueueJob(job.id)
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        .buttonStyle(.plain)
                                        .help("重试此文件")
                                    }
                                }
                                .font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 170)
                }
                .font(.caption2)
            }

            Divider()

            LabeledContent("今日已压缩", value: "\(model.todayCompressionCount) 项")
            HStack {
                LabeledContent("累计节省", value: model.formattedSize(model.totalSavedBytes))
                Spacer()
                Button {
                    isShowingSavingsCard = true
                } label: {
                    Label("成就战报", systemImage: "sparkles")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            if !model.purchaseManager.isPro {
                LabeledContent("自动额度", value: "图片 \(model.automaticImageCountToday)/15 · 视频 \(model.automaticVideoCountToday)/3")
                    .font(.caption)
            }

            HStack {
                if model.canUndoClipboardCompression {
                    Button("撤销剪贴板压缩") { model.undoClipboardCompression() }
                }
                Spacer()
                Button(model.isDropZoneVisible ? "隐藏压缩舱" : "显示压缩舱") { model.toggleDropZone() }
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: model.isWatchingFolder ? "folder.badge.eye" : "folder")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isWatchingFolder ? "文件夹监控已开启" : "文件夹监控已暂停")
                        .font(.callout.weight(.medium))
                    if let path = model.watchedFolderPath {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("在设置中选择截图或录屏文件夹")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("设置") { selectedTab = 1 }
                    .buttonStyle(.borderless)
            }

            if !model.history.isEmpty {
                Divider()
                Text("最近压缩")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.history.prefix(10)) { item in
                            HStack(spacing: 8) {
                                Image(systemName: icon(for: item.kind))
                                    .frame(width: 14)
                                    .foregroundStyle(.secondary)
                                Text(item.name).lineLimit(1)
                                Spacer(minLength: 8)
                                if item.kind == .imageFile && item.resultBytes >= item.originalBytes {
                                    Text("格式转换")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("−\(model.formattedSize(item.savedBytes))")
                                        .foregroundStyle(.secondary)
                                }
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
                                        Image(systemName: "ellipsis.circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .menuStyle(.borderlessButton)
                                }
                            }
                            .font(.caption)
                            .help("\(model.formattedSize(item.originalBytes)) → \(model.formattedSize(item.resultBytes))")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: 155)
            }

            Spacer(minLength: 0)
            Divider()
            Button("退出 DropSqueeze") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func icon(for kind: HistoryItem.Kind) -> String {
        switch kind {
        case .clipboardImage: return "doc.on.clipboard"
        case .imageFile: return "photo"
        case .videoFile: return "film"
        case .pdfFile: return "doc.text"
        }
    }

    private var queueSummary: String {
        if model.isManualQueuePaused { return "队列已暂停" }
        guard let remaining = model.estimatedQueueRemainingSeconds else {
            return "排队中还有 \(model.queuedFileCount) 个文件"
        }
        return "队列余 \(model.queuedFileCount) 个 · 约 \(max(1, Int(remaining.rounded()))) 秒"
    }
}
