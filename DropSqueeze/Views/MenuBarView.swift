import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab = 0

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

            Divider()

            LabeledContent("今日已压缩", value: "\(model.todayCompressionCount) 项")
            LabeledContent("累计节省", value: model.formattedSize(model.totalSavedBytes))
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
                                Text("−\(model.formattedSize(item.savedBytes))")
                                    .foregroundStyle(.secondary)
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
        }
    }
}
