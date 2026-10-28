import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject var settings: RulesSettings
    @ObservedObject var purchaseManager: PurchaseManager
    @State private var isShowingPrivacy = false
    @State private var newProfileName = ""
    @State private var videoMaximumSizeText = ""
    @State private var imageMaximumSizeText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Pro Banner Card
                proStatusHeader

                // Section: Language Settings
                settingsCard(title: L10n.tr("通用与语言"), icon: "globe") {
                    HStack {
                        Text(L10n.tr("界面语言"))
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Picker("", selection: $l10n.currentLanguage) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                }


                // Section: Automatic Processing
                settingsCard(title: L10n.tr("自动静默压缩"), icon: "bolt.badge.automatic.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(L10n.tr("自动压缩剪贴板图片"), isOn: Binding(
                            get: { settings.clipboardMonitoringEnabled },
                            set: { model.setClipboardMonitoringEnabled($0) }
                        ))
                        Toggle(L10n.tr("自动监控指定文件夹"), isOn: Binding(
                            get: { settings.folderMonitoringEnabled },
                            set: { model.setFolderMonitoringEnabled($0) }
                        ))
                        Toggle(L10n.tr("压缩完成后发送系统通知"), isOn: Binding(
                            get: { settings.notificationsEnabled },
                            set: { model.setNotificationsEnabled($0) }
                        ))
                        Toggle(L10n.tr("压缩完成后播放提示音"), isOn: Binding(
                            get: { settings.completionSoundEnabled },
                            set: { settings.setCompletionSoundEnabled($0) }
                        ))

                        if settings.completionSoundEnabled {
                            HStack(spacing: 8) {
                                Picker(L10n.tr("提示音效"), selection: Binding(
                                    get: { CompressionFeedbackSound(rawValue: settings.completionSoundName) ?? .pop },
                                    set: { settings.setCompletionSoundName($0.rawValue) }
                                )) {
                                    ForEach(CompressionFeedbackSound.allCases) { sound in
                                        Text(sound.title).tag(sound)
                                    }
                                }
                                .pickerStyle(.menu)

                                Button {
                                    CompressionFeedbackController.shared.playFeedback(soundName: settings.completionSoundName, haptics: false)
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.tactile)
                                .help(L10n.tr("试听此音效"))
                            }
                            .padding(.leading, 18)
                        }

                        Toggle(L10n.tr("启用触觉震动反馈 (Force Touch)"), isOn: Binding(
                            get: { settings.hapticFeedbackEnabled },
                            set: { settings.setHapticFeedbackEnabled($0) }
                        ))

                        Text(L10n.tr("DropSqueeze 始终保留原文件并在后台静默输出更小副本；剪贴板处理不会产生冗余文件。"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Section: Output Directory
                settingsCard(title: L10n.tr("保存与输出目录"), icon: "folder.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: model.outputFolderURL == nil ? "folder" : "folder.badge.gearshape")
                                .foregroundStyle(Color.accentColor)
                            Text(
                                model.requiresOutputFolderAuthorization
                                    ? (model.outputFolderURL?.lastPathComponent ?? L10n.tr("输出文件夹无法访问"))
                                    : (model.outputFolderURL?.lastPathComponent ?? L10n.tr("默认保存到原文件所在同级目录"))
                            )
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        }

                        if let outputFolderURL = model.outputFolderURL {
                            Text(outputFolderURL.path)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }

                        if model.requiresOutputFolderAuthorization {
                            Text(L10n.tr("请重新选择此文件夹授权，或恢复默认同级位置。"))
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }

                        HStack(spacing: 8) {
                            Button(L10n.tr("更改输出目录")) { model.chooseOutputFolder() }
                                .buttonStyle(.tactile)
                                .controlSize(.small)

                            if model.outputFolderURL != nil || model.requiresOutputFolderAuthorization {
                                Button(L10n.tr("恢复默认同级")) { model.resetOutputFolder() }
                                    .buttonStyle(.tactile)
                                    .controlSize(.small)
                            }
                            Spacer()
                        }
                    }
                }

                // Section: Video Transcoding Settings
                settingsCard(title: L10n.tr("视频压制与静音转码"), icon: "film.stack.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(L10n.tr("画质预设档位"), selection: Binding(
                            get: { settings.videoOutputPreset },
                            set: { model.setVideoOutputPreset($0) }
                        )) {
                            ForEach(VideoOutputPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }

                        Picker(L10n.tr("视频编码格式"), selection: Binding(
                            get: { settings.videoCodecPreference },
                            set: { settings.setVideoCodecPreference($0) }
                        )) {
                            ForEach(VideoCodecPreference.allCases) { codec in
                                Text(codec.title).tag(codec)
                            }
                        }

                        Picker(L10n.tr("目标码率品质"), selection: Binding(
                            get: { settings.videoBitrateTarget },
                            set: { settings.setVideoBitrateTarget($0) }
                        )) {
                            ForEach(VideoBitrateTarget.allCases) { target in
                                Text(target.title).tag(target)
                            }
                        }

                        Picker(L10n.tr("帧率上限限制"), selection: Binding(
                            get: { settings.videoFrameRate },
                            set: { settings.setVideoFrameRate($0) }
                        )) {
                            ForEach(VideoFrameRate.allCases) { rate in
                                Text(rate.title).tag(rate)
                            }
                        }

                        Toggle(L10n.tr("保留视频原音频轨道"), isOn: Binding(
                            get: { settings.videoIncludesAudio },
                            set: { settings.setVideoIncludesAudio($0) }
                        ))

                        HStack(spacing: 8) {
                            Text(L10n.tr("自定义体积上限"))
                                .font(.system(size: 11))
                            TextField(L10n.tr("留空使用预设"), text: $videoMaximumSizeText)
                                .textFieldStyle(.roundedBorder)
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
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Text(L10n.tr("关闭保留音频将自动剥离音频音轨，录屏体积可减小 30%–60% 并彻底消除环境杂音。"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Section: Preset Scenarios & Profiles
                settingsCard(title: L10n.tr("平台一键预设与方案"), icon: "slider.horizontal.3") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("一键应用符合各主流工作流的硬指标参数配置："))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), alignment: .leading, spacing: 6) {
                            ForEach(CompressionScenario.allCases) { scenario in
                                Button(scenario.requiredProFeature == nil ? scenario.title : "\(scenario.title) · Pro") {
                                    model.applyCompressionScenario(scenario)
                                }
                                .buttonStyle(.tactile)
                                .controlSize(.small)
                                .help(scenario.detail)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("方案名称（例如：微信公众号图）", text: $newProfileName)
                                .textFieldStyle(.roundedBorder)
                            Button(L10n.tr("保存当前配置")) {
                                guard settings.saveCurrentProfile(name: newProfileName) != nil else { return }
                                newProfileName = ""
                            }
                            .buttonStyle(.tactile)
                            .controlSize(.small)
                            .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if !settings.savedProfiles.isEmpty {
                            VStack(spacing: 4) {
                                ForEach(settings.savedProfiles) { profile in
                                    HStack {
                                        Text(profile.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        Spacer()
                                        Button(L10n.tr("应用")) { model.applySavedProfile(profile) }
                                            .buttonStyle(.tactile)
                                            .controlSize(.mini)
                                        Button {
                                            settings.deleteProfile(profile.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("删除此配置")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }

                // Section: Image Compression Strategy
                settingsCard(title: L10n.tr("图片与动图压缩"), icon: "photo.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(L10n.tr("文件输出格式"), selection: Binding(
                            get: { settings.imageFileOutputFormat },
                            set: { model.setImageFileOutputFormat($0) }
                        )) {
                            ForEach(ImageFileOutputFormat.allCases) { format in
                                Text(format.title)
                                    .tag(format)
                                    .disabled(format.typeIdentifier.map { !ImageCompressor.encodingAvailable(for: $0) } ?? false)
                            }
                        }

                        Picker(L10n.tr("最长边分辨率上限"), selection: Binding(
                            get: { settings.imageResizePreset },
                            set: { settings.setImageResizePreset($0) }
                        )) {
                            ForEach(ImageResizePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }

                        HStack(spacing: 10) {
                            Text(L10n.tr("有损压缩画质"))
                                .font(.system(size: 11))
                            Slider(value: Binding(
                                get: { settings.imageQuality },
                                set: { settings.setImageQuality($0) }
                            ), in: 0.4...0.96, step: 0.04)
                            Text("\(Int(settings.imageQuality * 100))%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                        }

                        HStack(spacing: 8) {
                            Text("图片体积上限")
                                .font(.system(size: 11))
                            TextField("留空关闭", text: $imageMaximumSizeText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 108)
                                .onAppear {
                                    imageMaximumSizeText = settings.imageMaximumSizeMB.map { String(format: "%.1f", $0) } ?? ""
                                }
                                .onChange(of: imageMaximumSizeText) { value in
                                    let filtered = String(value.filter { $0.isNumber || $0 == "." }.prefix(7))
                                    if filtered != value {
                                        imageMaximumSizeText = filtered
                                        return
                                    }
                                    guard !filtered.isEmpty else {
                                        settings.setImageMaximumSizeMB(nil)
                                        return
                                    }
                                    guard let requestedSize = Double(filtered), requestedSize.isFinite else { return }
                                    let boundedSize = min(max(requestedSize, ImageOutputSizeLimit.minimumMegabytes), ImageOutputSizeLimit.maximumMegabytes)
                                    if boundedSize != requestedSize {
                                        imageMaximumSizeText = String(format: "%.1f", boundedSize)
                                    }
                                    settings.setImageMaximumSizeMB(boundedSize)
                                }
                                .onChange(of: settings.imageMaximumSizeMB) { value in
                                    let storedValue = value.map { String(format: "%.1f", $0) } ?? ""
                                    if storedValue != imageMaximumSizeText {
                                        imageMaximumSizeText = storedValue
                                    }
                                }
                            Text("MB")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Toggle(L10n.tr("移除 EXIF、GPS 拍摄地点与隐私元数据"), isOn: Binding(
                            get: { settings.stripImageMetadata },
                            set: { settings.setStripImageMetadata($0) }
                        ))

                        Text("设置体积上限后，DropSqueeze 会尽量以最高画质达标；动图仍保持 GIF 格式。剪贴板图片也使用此上限。")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Section: Automation Workflow Recipes
                settingsCard(title: "自动化流程配方", icon: "arrow.triangle.2.circlepath") {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("把监控范围、压缩配置、文件筛选和输出命名保存成可复用配方；在其他监控目录中套用后，保存目录规则即可开始自动处理。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        if settings.automationRecipes.isEmpty {
                            Text("配方会从监控目录规则中创建。添加一个目录并配置规则后，选择「保存为流程配方」。")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(settings.automationRecipes) { recipe in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: recipe.isAvailable(savedProfiles: settings.savedProfiles)
                                          ? "arrow.triangle.2.circlepath"
                                          : "exclamationmark.triangle.fill")
                                        .foregroundStyle(recipe.isAvailable(savedProfiles: settings.savedProfiles)
                                                         ? Color.accentColor
                                                         : Color.orange)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipe.name)
                                            .font(.system(size: 10.5, weight: .semibold))
                                        Text(recipe.summary(savedProfiles: settings.savedProfiles))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 2)
                                    Button {
                                        settings.deleteAutomationRecipe(recipe.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("删除流程配方")
                                }
                                .padding(.vertical, 4)
                                if recipe.id != settings.automationRecipes.last?.id {
                                    Divider().opacity(0.3)
                                }
                            }
                            Text("最多保存 \(RulesSettings.maximumAutomationRecipeCount) 个配方。删除配方不会移除已保存到目录的规则。")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Section: Monitored Folders
                settingsCard(title: L10n.tr("文件夹实时自动监控"), icon: "folder.badge.eye") {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.monitoredFolders.isEmpty {
                            Text(L10n.tr("尚未添加监控文件夹。可将系统的「截屏」或「录屏」存放目录加入监控。"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(model.monitoredFolders) { folder in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: model.isFolderWatching(folder) ? "folder.badge.eye" : "folder")
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(folder.displayName)
                                            .font(.system(size: 11, weight: .semibold))
                                            .lineLimit(1)
                                        Text(folder.path)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Button {
                                        model.removeWatchedFolder(folder)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("移除此监控文件夹")
                                }

                                FolderRuleEditor(model: model, folder: folder)

                                if folder.id != model.monitoredFolders.last?.id {
                                    Divider().opacity(0.3)
                                }
                            }
                        }

                        HStack {
                            Button {
                                model.chooseWatchedFolder()
                            } label: {
                                Label(L10n.tr("添加监控目录"), systemImage: "plus")
                            }
                            .buttonStyle(.tactile)
                            .controlSize(.small)

                            Spacer()

                            if !model.monitoredFolders.isEmpty {
                                StatusBadge(
                                    title: model.isWatchingFolder ? "监控中" : "已暂停",
                                    color: model.isWatchingFolder ? .green : .secondary,
                                    isSubtle: true
                                )
                            }
                        }

                        if !purchaseManager.isPro && !model.monitoredFolders.isEmpty {
                            Text(L10n.tr("免费版可监控 1 个文件夹；添加更多目录需要 Pro 权限。"))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Section: PDF & Pro Rules
                settingsCard(title: L10n.tr("PDF 与 Pro 高级规则"), icon: "sparkles") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("Pro 可智能重采样优化 PDF 内嵌位图，保留全部矢量文本与表格结构。"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        if !purchaseManager.isPro {
                            Button(L10n.tr("解锁 PDF 高级压缩")) { model.requestPro(for: .pdfCompression) }
                                .buttonStyle(.tactile)
                                .controlSize(.small)
                        }

                        Divider().opacity(0.3)

                        ForEach(ProFeature.allCases.filter { $0 != .fileWebPOutput }) { feature in
                            Toggle(isOn: Binding(
                                get: { settings.isEnabled(feature) },
                                set: { model.setProFeature(feature, enabled: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.system(size: 11, weight: .medium))
                                    Text(feature.detail)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .disabled(
                                (feature == .clipboardWebPOutput || feature == .fileWebPOutput)
                                    && !ImageCompressor.webPEncodingAvailable
                            )
                        }
                    }
                }

                // Section: Shortcuts & Finder Quick Actions
                settingsCard(title: L10n.tr("快捷指令与 Finder 联动"), icon: "command") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("在 macOS「快捷指令」中可直接调用“压缩媒体文件”动作；在 Finder 中右键快速操作亦可一键调用。"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                // Section: Privacy & Storage
                settingsCard(title: L10n.tr("隐私安全与数据保护"), icon: "lock.shield.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("所有媒体运算 100% 在 Mac 本地完成；绝不上传任何图片、视频或剪贴板隐私。"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button(L10n.tr("查看隐私声明")) { isShowingPrivacy = true }
                                .buttonStyle(.tactile)
                                .controlSize(.small)

                            Spacer()

                            Button(L10n.tr("清空本地历史记录")) { model.clearHistory() }
                                .buttonStyle(.tactile)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .padding(14)
        }
        .sheet(isPresented: $isShowingPrivacy) {
            PrivacyPolicyView()
        }
    }

    // MARK: - Pro Status Header

    private var proStatusHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(purchaseManager.isPro ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.08))
                    .frame(width: 32, height: 32)
                Image(systemName: purchaseManager.isPro ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(purchaseManager.isPro ? Color.accentColor : Color.primary)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(purchaseManager.isPro ? L10n.tr("DropSqueeze Pro 已激活") : L10n.tr("DropSqueeze 免费版"))
                        .font(.system(size: 13, weight: .bold))
                    if purchaseManager.isPro {
                        StatusBadge(title: "PRO", color: .accentColor)
                    }
                }
                Text(purchaseManager.isPro ? L10n.tr("享有无限自动处理、PDF 重采样、多目录监控与全量高级规则") : L10n.tr("每日免费额度：图片 15 张 · 视频 3 个 · 单目录监控"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !purchaseManager.isPro {
                Button(L10n.tr("升级 Pro")) { model.requestPro(for: .general) }
                    .buttonStyle(.tactile)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            purchaseManager.isPro
                ? Color.accentColor.opacity(0.08)
                : Color.white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    purchaseManager.isPro ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Reusable Settings Card Container

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct FolderRuleEditor: View {
    @ObservedObject var model: AppModel
    let folder: MonitoredFolder
    @State private var rule: FolderWatchRule
    @State private var maximumSizeText: String
    @State private var automationRecipeName = ""
    @State private var automationRecipeFeedback: String?

    init(model: AppModel, folder: MonitoredFolder) {
        self.model = model
        self.folder = folder
        _rule = State(initialValue: folder.rule)
        _maximumSizeText = State(initialValue: folder.rule.maximumFileSizeMB.map(String.init) ?? "")
    }

    var body: some View {
        DisclosureGroup("监控规则配置 · \(folder.rule.scope.title)") {
            VStack(alignment: .leading, spacing: 8) {
                if !model.settings.automationRecipes.isEmpty {
                    Menu {
                        ForEach(model.settings.automationRecipes) { recipe in
                            Button {
                                guard recipe.isAvailable(savedProfiles: model.settings.savedProfiles) else {
                                    automationRecipeFeedback = "此配方使用的压缩配置已删除，请先选择可用配置。"
                                    return
                                }
                                rule = recipe.rule
                                maximumSizeText = recipe.rule.maximumFileSizeMB.map(String.init) ?? ""
                                automationRecipeFeedback = "已套用「\(recipe.name)」；保存目录规则后生效。"
                            } label: {
                                Text(recipe.isAvailable(savedProfiles: model.settings.savedProfiles)
                                     ? recipe.name
                                     : "\(recipe.name) · 配置已删除")
                            }
                            .disabled(!recipe.isAvailable(savedProfiles: model.settings.savedProfiles))
                        }
                    } label: {
                        Label("套用流程配方", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.tactile)
                    .controlSize(.small)
                }

                Picker("压缩配置", selection: $rule.compressionProfileIdentifier) {
                    if !rule.usesCurrentCompressionProfile,
                       rule.resolvedCompressionProfile(savedProfiles: model.settings.savedProfiles) == nil {
                        Text("已删除的配置").tag(rule.compressionProfileIdentifier)
                    }
                    Text("使用当前设置").tag(CompressionProfileReference.currentIdentifier)
                    ForEach(CompressionScenario.allCases) { scenario in
                        let identifier = CompressionProfileReference.identifier(for: scenario)
                        Text(scenario.requiredProFeature == nil ? scenario.title : "\(scenario.title) · Pro")
                            .tag(identifier)
                    }
                    if !model.settings.savedProfiles.isEmpty {
                        Divider()
                        ForEach(model.settings.savedProfiles) { profile in
                            Text(profile.name)
                                .tag(CompressionProfileReference.identifier(for: profile))
                        }
                    }
                }
                Picker("处理文件类型", selection: $rule.scope) {
                    ForEach(FolderWatchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                Toggle("包含子文件夹 (递归监控)", isOn: $rule.includeSubfolders)
                TextField("文件名必须包含（可留空）", text: $rule.filenameContains)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("最大文件大小")
                    TextField("不限", text: $maximumSizeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onChange(of: maximumSizeText) { value in
                            let digits = String(value.filter(\.isNumber).prefix(7))
                            if digits != value { maximumSizeText = digits }
                        }
                    Text("MB")
                }

                TextField("输出命名模板：{name}-compressed", text: $rule.outputNameTemplate)
                    .textFieldStyle(.roundedBorder)
                Text("可用变量：{name} 原文件名，{date} 当前日期。原文件始终保留。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 6) {
                    TextField("新配方名称", text: $automationRecipeName)
                        .textFieldStyle(.roundedBorder)
                    Button("保存为配方") { saveAutomationRecipe() }
                        .buttonStyle(.tactile)
                        .controlSize(.small)
                        .disabled(automationRecipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let automationRecipeFeedback {
                    Text(automationRecipeFeedback)
                        .font(.system(size: 9.5))
                        .foregroundStyle(automationRecipeFeedback.hasPrefix("已") ? .green : .orange)
                }

                HStack {
                    Spacer()
                    Button("保存此目录规则") {
                        model.updateFolderRule(folder.id, rule: currentRuleForSaving())
                    }
                    .buttonStyle(.tactile)
                    .controlSize(.small)
                }
            }
            .padding(.top, 6)
        }
        .font(.system(size: 11))
    }

    private func currentRuleForSaving() -> FolderWatchRule {
        var savedRule = rule
        savedRule.maximumFileSizeMB = Int(maximumSizeText).flatMap { $0 > 0 ? $0 : nil }
        if savedRule.outputNameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            savedRule.outputNameTemplate = "{name}-compressed"
        }
        return savedRule
    }

    private func saveAutomationRecipe() {
        guard let recipe = model.settings.saveAutomationRecipe(
            name: automationRecipeName,
            rule: currentRuleForSaving()
        ) else {
            automationRecipeFeedback = "无法保存：名称最多 40 字、筛选词最多 80 字、模板最多 120 字；检查压缩配置，配方上限为 \(RulesSettings.maximumAutomationRecipeCount) 个。"
            return
        }
        automationRecipeName = ""
        automationRecipeFeedback = "已保存流程配方「\(recipe.name)」"
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.tr("隐私安全说明"))
                        .font(.system(size: 16, weight: .bold))
                }
                Spacer()
                Button(L10n.tr("完成")) { dismiss() }
                    .buttonStyle(.tactile)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    policySection("100% Mac 本地运算", "所有图片有损/无损压缩、视频硬件编码、Vision 端侧 OCR 提取及剪贴板处理全部在您的 Mac 本机完成，不会向开发者或任何第三方服务器上传任何字节。")
                    policySection("剪贴板保护", "启用剪贴板监控后，仅在检测到新复制的图片或媒体 URL 时生成更小副本并置回剪贴板；应用通过内部私有标记防止循环触发。")
                    policySection("沙盒安全与书签授权", "选择的监控文件夹及输出目录仅在本机通过 App Sandbox 安全作用域书签持久化，您可随时在设置中暂停监控或移除文件夹。")
                    policySection("购买与权限", "应用内购买通过 Apple StoreKit 2 官方系统框架验证，DropSqueeze 不收集任何支付卡号或 Apple ID 凭证。")

                    Text("隐私协议版本：2026 年 10 月 · 纯端侧零云端架构")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 460, height: 440)
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
