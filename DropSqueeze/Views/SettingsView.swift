import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RulesSettings
    @ObservedObject var purchaseManager: PurchaseManager
    @State private var isShowingPrivacy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(purchaseManager.isPro ? "DropSqueeze Pro" : "免费版")
                            .font(.headline)
                        Text(purchaseManager.isPro
                             ? "Pro 权限已启用"
                             : "每日自动额度：图片 15 张 · 视频 3 个")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !purchaseManager.isPro {
                        Button("升级 Pro") { model.requestPro(for: .general) }
                            .buttonStyle(.borderedProminent)
                    }
                }

                GroupBox("自动处理") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("自动压缩剪贴板图片", isOn: Binding(
                            get: { settings.clipboardMonitoringEnabled },
                            set: { model.setClipboardMonitoringEnabled($0) }
                        ))
                        Toggle("监控截图和录屏文件夹", isOn: Binding(
                            get: { settings.folderMonitoringEnabled },
                            set: { model.setFolderMonitoringEnabled($0) }
                        ))
                        Text("只处理名称包含截图或录屏字样的图片，以及录屏 MOV。原文件会保留。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("监控文件夹") {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.monitoredFolders.isEmpty {
                            Text("尚未添加文件夹")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.monitoredFolders) { folder in
                            HStack(spacing: 8) {
                                Image(systemName: model.isFolderWatching(folder) ? "folder.badge.eye" : "folder")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.displayName).lineLimit(1)
                                    Text(folder.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Button {
                                    model.removeWatchedFolder(folder)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .help("移除此监控文件夹")
                            }
                        }
                        HStack {
                            Button {
                                model.chooseWatchedFolder()
                            } label: {
                                Label("添加文件夹", systemImage: "plus")
                            }

                            Spacer()
                            if !model.monitoredFolders.isEmpty {
                                Text(model.isWatchingFolder ? "监控中" : "已暂停")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !purchaseManager.isPro && !model.monitoredFolders.isEmpty {
                            Text("免费版可监控一个文件夹；添加第二个文件夹需要 Pro。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Pro 规则") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ProFeature.allCases) { feature in
                            Toggle(isOn: Binding(
                                get: { settings.isEnabled(feature) },
                                set: { model.setProFeature(feature, enabled: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(feature.title)
                                    Text(feature.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .disabled(feature == .webPOutput && !ImageCompressor.webPEncodingAvailable)
                        }
                        if !ImageCompressor.webPEncodingAvailable {
                            Text("当前系统版本不提供 WebP 编码，升级 macOS 后可用。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("隐私与数据") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("媒体处理在本机完成。剪贴板内容、文件和压缩历史不会上传。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("查看隐私说明") { isShowingPrivacy = true }
                            Spacer()
                            Button("清除本地历史") { model.clearHistory() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(12)
        }
        .sheet(isPresented: $isShowingPrivacy) {
            PrivacyPolicyView()
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("隐私说明").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    policySection("本机处理", "图片、视频和剪贴板内容只在 Mac 本机处理。应用不会将这些内容上传到开发者服务器。")
                    policySection("剪贴板", "启用剪贴板监控后，应用会读取新复制的支持格式图片或文件 URL，以生成更小的本地副本。压缩结果写回剪贴板前会附带内部标记，避免重复处理。")
                    policySection("文件夹授权", "你选择的文件夹路径和安全书签保存在本机应用偏好设置中，用于在下次启动时恢复监控。你可以在设置中移除文件夹或暂停监控。")
                    policySection("历史记录", "最近压缩项目、文件名和节省空间统计保存在本机。使用“清除本地历史”可删除最近项目记录；累计节省统计会保留。")
                    policySection("购买", "购买和恢复由 Apple App Store 处理。应用读取 StoreKit 返回的商品和已验证购买权限，不接收支付卡信息。")
                    Text("隐私说明版本：2026 年 10 月 26 日")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(width: 460, height: 440)
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary)
        }
    }
}
