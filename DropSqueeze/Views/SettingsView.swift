import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: RulesSettings
    @ObservedObject var purchaseManager: PurchaseManager
    @State private var isShowingPrivacy = false
    @State private var newProfileName = ""
    @State private var videoMaximumSizeText = ""

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
                        Toggle("自动监控文件夹", isOn: Binding(
                            get: { settings.folderMonitoringEnabled },
                            set: { model.setFolderMonitoringEnabled($0) }
                        ))
                        Toggle("压缩完成后显示通知", isOn: Binding(
                            get: { settings.notificationsEnabled },
                            set: { model.setNotificationsEnabled($0) }
                        ))
                        Text("每个文件夹可以分别设置媒体类型、递归范围、文件名、大小上限和输出命名。原文件会保留。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("首次显示通知时，macOS 会请求通知权限。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("压缩结果") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            model.requiresOutputFolderAuthorization
                                ? (model.outputFolderURL?.lastPathComponent ?? "输出文件夹无法访问")
                                : (model.outputFolderURL?.lastPathComponent ?? "保存到各原文件所在文件夹"),
                            systemImage: model.outputFolderURL == nil ? "folder" : "folder.fill"
                        )
                        .lineLimit(1)
                        .help(model.outputFolderURL?.path ?? "")
                        if let outputFolderURL = model.outputFolderURL {
                            Text(outputFolderURL.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        if model.requiresOutputFolderAuthorization {
                            Text("请重新选择此文件夹，或恢复默认位置。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        HStack {
                            Button("选择文件夹") { model.chooseOutputFolder() }
                            Spacer()
                            if model.outputFolderURL != nil || model.requiresOutputFolderAuthorization {
                                Button("恢复默认") { model.resetOutputFolder() }
                                    .buttonStyle(.borderless)
                            }
                        }
                        Text("拖入文件、自动监控和快捷指令共用此位置。原文件始终保留。剪贴板压缩不会生成文件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("视频输出") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("压缩预设", selection: Binding(
                            get: { settings.videoOutputPreset },
                            set: { model.setVideoOutputPreset($0) }
                        )) {
                            ForEach(VideoOutputPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        Picker("视频编码", selection: Binding(
                            get: { settings.videoCodecPreference },
                            set: { settings.setVideoCodecPreference($0) }
                        )) {
                            ForEach(VideoCodecPreference.allCases) { codec in
                                Text(codec.title).tag(codec)
                            }
                        }
                        Picker("码率 / 画质目标", selection: Binding(
                            get: { settings.videoBitrateTarget },
                            set: { settings.setVideoBitrateTarget($0) }
                        )) {
                            ForEach(VideoBitrateTarget.allCases) { target in
                                Text(target.title).tag(target)
                            }
                        }
                        Picker("帧率", selection: Binding(
                            get: { settings.videoFrameRate },
                            set: { settings.setVideoFrameRate($0) }
                        )) {
                            ForEach(VideoFrameRate.allCases) { rate in
                                Text(rate.title).tag(rate)
                            }
                        }
                        Toggle("保留原视频音频", isOn: Binding(
                            get: { settings.videoIncludesAudio },
                            set: { settings.setVideoIncludesAudio($0) }
                        ))
                        HStack {
                            Text("自定义最大体积")
                            TextField("留空使用预设", text: $videoMaximumSizeText)
                                .frame(width: 108)
                                .onAppear {
                                    videoMaximumSizeText = settings.videoMaximumSizeMB.map(String.init) ?? ""
                                }
                                .onChange(of: videoMaximumSizeText) { value in
                                    let digits = String(value.filter(\.isNumber).prefix(4))
                                    if digits != value {
                                        videoMaximumSizeText = digits
                                        return
                                    }
                                    guard let requestedSize = Int(digits) else {
                                        settings.setVideoMaximumSizeMB(nil)
                                        return
                                    }
                                    let boundedSize = min(requestedSize, 5_000)
                                    if boundedSize != requestedSize {
                                        videoMaximumSizeText = String(boundedSize)
                                    }
                                    settings.setVideoMaximumSizeMB(boundedSize)
                                }
                                .onChange(of: settings.videoMaximumSizeMB) { value in
                                    let storedValue = value.map(String.init) ?? ""
                                    if storedValue != videoMaximumSizeText {
                                        videoMaximumSizeText = storedValue
                                    }
                                }
                            Text("MB")
                                .foregroundStyle(.secondary)
                        }
                        Text(settings.videoOutputPreset.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("自定义体积为 1–5000 MB；填写后会替代预设中的 10/25 MB 上限，输出分辨率仍按当前预设执行。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("H.264 兼容性更广；HEVC 通常更省空间。设置自定义上限后会从原件尝试更低输出档位，并检查实际大小。可设置最高帧率或移除音轨；仍无法达标时会保留原文件并说明原因。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("处理预设与自定义配置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("预设会更新全局压缩设置，并同时用于拖入文件、剪贴板、监控文件夹和快捷指令。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            ForEach(CompressionScenario.allCases) { scenario in
                                Button(scenario.title) { model.applyCompressionScenario(scenario) }
                                    .buttonStyle(.bordered)
                                    .help(scenario.detail)
                            }
                        }
                        HStack {
                            TextField("配置名称", text: $newProfileName)
                            Button("保存当前设置") {
                                guard settings.saveCurrentProfile(name: newProfileName) != nil else { return }
                                newProfileName = ""
                            }
                            .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        ForEach(settings.savedProfiles) { profile in
                            HStack {
                                Text(profile.name).lineLimit(1)
                                Spacer()
                                Button("应用") { model.applySavedProfile(profile) }
                                Button {
                                    settings.deleteProfile(profile.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("删除此配置")
                            }
                            .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("图片输出") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("文件输出格式", selection: Binding(
                            get: { settings.imageFileOutputFormat },
                            set: { model.setImageFileOutputFormat($0) }
                        )) {
                            ForEach(ImageFileOutputFormat.allCases) { format in
                                Text(format.title)
                                    .tag(format)
                                    .disabled(format.typeIdentifier.map { !ImageCompressor.encodingAvailable(for: $0) } ?? false)
                            }
                        }
                        Picker("最长边上限", selection: Binding(
                            get: { settings.imageResizePreset },
                            set: { settings.setImageResizePreset($0) }
                        )) {
                            ForEach(ImageResizePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        HStack(spacing: 10) {
                            Text("有损编码质量")
                            Slider(value: Binding(
                                get: { settings.imageQuality },
                                set: { settings.setImageQuality($0) }
                            ), in: 0.4...0.96, step: 0.04)
                            Text("\(Int(settings.imageQuality * 100))%")
                                .monospacedDigit()
                                .frame(width: 38, alignment: .trailing)
                        }
                        Toggle("移除 EXIF、GPS 与注释信息", isOn: Binding(
                            get: { settings.stripImageMetadata },
                            set: { settings.setStripImageMetadata($0) }
                        ))
                        Text("输出格式只影响文件图片；选择 JPEG、HEIC、PNG 或 WebP 时会按指定格式生成副本，即使新文件更大也会保留。JPEG 不支持透明背景。动图始终保持 GIF。剪贴板只应用像素上限和质量设置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("像素上限对剪贴板和文件都生效，并保持长宽比。质量滑块影响 JPEG、HEIC 和 WebP；PNG、TIFF 与 GIF 使用无损像素编码。")
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
                            VStack(alignment: .leading, spacing: 8) {
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
                                FolderRuleEditor(model: model, folder: folder)
                                if folder.id != model.monitoredFolders.last?.id {
                                    Divider()
                                }
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

                GroupBox("PDF 压缩") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pro 会优化 PDF 内嵌图片，同时保留文本与矢量内容。加密或带数字签名的 PDF 会跳过；压缩结果另存为副本，原件不变。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !purchaseManager.isPro {
                            Button("解锁 PDF 压缩") { model.requestPro(for: .pdfCompression) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Pro 规则") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ProFeature.allCases.filter { $0 != .fileWebPOutput }) { feature in
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
                            .disabled(
                                (feature == .clipboardWebPOutput || feature == .fileWebPOutput)
                                    && !ImageCompressor.webPEncodingAvailable
                            )
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

                GroupBox("Finder 与快捷指令") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("在 macOS「快捷指令」中添加“压缩媒体文件”动作，可把选中的图片或视频压缩后作为新文件返回。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("要从 Finder 使用：新建快捷指令，启用“用作快速操作”，接收 Finder 文件并添加 DropSqueeze 动作。原文件会保留。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

private struct FolderRuleEditor: View {
    @ObservedObject var model: AppModel
    let folder: MonitoredFolder
    @State private var rule: FolderWatchRule
    @State private var maximumSizeText: String

    init(model: AppModel, folder: MonitoredFolder) {
        self.model = model
        self.folder = folder
        _rule = State(initialValue: folder.rule)
        _maximumSizeText = State(initialValue: folder.rule.maximumFileSizeMB.map(String.init) ?? "")
    }

    var body: some View {
        DisclosureGroup("监控规则 · \(folder.rule.scope.title)") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("处理文件", selection: $rule.scope) {
                    ForEach(FolderWatchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                Toggle("包含子文件夹", isOn: $rule.includeSubfolders)
                TextField("文件名必须包含（可留空）", text: $rule.filenameContains)
                HStack {
                    Text("最大文件大小 MB")
                    TextField("不限", text: $maximumSizeText)
                        .frame(width: 72)
                        .onChange(of: maximumSizeText) { value in
                            let digits = String(value.filter(\.isNumber).prefix(7))
                            if digits != value { maximumSizeText = digits }
                        }
                }
                TextField("输出名称模板：{name}-compressed", text: $rule.outputNameTemplate)
                Text("可用变量：{name} 原文件名，{date} 日期。原文件会保留。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("保存规则") {
                        rule.maximumFileSizeMB = Int(maximumSizeText).flatMap { $0 > 0 ? $0 : nil }
                        if rule.outputNameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            rule.outputNameTemplate = "{name}-compressed"
                        }
                        model.updateFolderRule(folder.id, rule: rule)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 6)
        }
        .font(.caption)
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
