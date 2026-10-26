import AppIntents
import UniformTypeIdentifiers

enum ShortcutVideoPreset: String, AppEnum {
    case compact10MB
    case share25MB
    case standard720p
    case high1080p

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "视频预设覆盖")

    static var caseDisplayRepresentations: [ShortcutVideoPreset: DisplayRepresentation] = [
        .compact10MB: DisplayRepresentation(title: "最多 10 MB"),
        .share25MB: DisplayRepresentation(title: "最多 25 MB"),
        .standard720p: DisplayRepresentation(title: "标准 720p"),
        .high1080p: DisplayRepresentation(title: "清晰 1080p")
    ]

    var outputPreset: VideoOutputPreset {
        VideoOutputPreset(rawValue: rawValue) ?? .standard720p
    }
}

enum ShortcutOutputDestination: String, AppEnum {
    case appDefault
    case sameAsSource

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "输出位置")

    static var caseDisplayRepresentations: [ShortcutOutputDestination: DisplayRepresentation] = [
        .appDefault: DisplayRepresentation(title: "DropSqueeze 当前保存位置"),
        .sameAsSource: DisplayRepresentation(title: "与原件放在一起")
    ]

    var modelValue: CompressionOutputDestination {
        CompressionOutputDestination(rawValue: rawValue) ?? .appDefault
    }
}

struct ShortcutCompressionProfile: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "压缩配置")
    static var defaultQuery = ShortcutCompressionProfileQuery()

    let id: String
    let displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: displayName))
    }

    static let current = ShortcutCompressionProfile(
        id: CompressionProfileReference.currentIdentifier,
        displayName: "使用当前设置"
    )
}

struct ShortcutCompressionProfileQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ShortcutCompressionProfile] {
        let available = await Self.availableProfiles()
        let identifierSet = Set(identifiers)
        return available.filter { identifierSet.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ShortcutCompressionProfile] {
        await Self.availableProfiles()
    }

    func defaultResult() async -> ShortcutCompressionProfile? {
        .current
    }

    private static func availableProfiles() async -> [ShortcutCompressionProfile] {
        await MainActor.run {
            let scenarios = CompressionScenario.allCases.map { scenario in
                ShortcutCompressionProfile(
                    id: CompressionProfileReference.identifier(for: scenario),
                    displayName: scenario.title
                )
            }
            let savedProfiles = AppModel.shared?.settings.savedProfiles.map { profile in
                ShortcutCompressionProfile(
                    id: CompressionProfileReference.identifier(for: profile),
                    displayName: profile.name
                )
            } ?? []
            return [.current] + scenarios + savedProfiles
        }
    }
}

struct CompressMediaFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "压缩媒体文件"
    static var description = IntentDescription("选择场景或已保存配置，指定视频体积上限和输出位置；原文件始终保留。")
    static var openAppWhenRun = true

    @Parameter(
        title: "要压缩的文件",
        supportedTypeIdentifiers: ["public.image", "public.movie", "com.adobe.pdf"]
    )
    var files: [IntentFile]

    @Parameter(title: "压缩配置", default: nil)
    var profile: ShortcutCompressionProfile?

    @Parameter(title: "视频预设覆盖", default: nil)
    var videoPreset: ShortcutVideoPreset?

    @Parameter(title: "视频最大体积（MB）", default: nil)
    var maximumVideoSizeMB: Int?

    @Parameter(title: "输出位置", default: .appDefault)
    var outputDestination: ShortcutOutputDestination

    static var parameterSummary: some ParameterSummary {
        Summary("压缩 \(\.$files)，使用 \(\.$profile)，视频预设 \(\.$videoPreset)，上限 \(\.$maximumVideoSizeMB) MB，保存到 \(\.$outputDestination)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let inputURLs = files.compactMap(\.fileURL)
        guard inputURLs.count == files.count else {
            throw ShortcutIntentError.unavailableFiles
        }

        let outputURLs = try await ShortcutCompressionBridge.compress(
            inputURLs,
            profileIdentifier: profile?.id ?? CompressionProfileReference.currentIdentifier,
            videoPresetOverride: videoPreset?.outputPreset,
            maximumVideoSizeMB: maximumVideoSizeMB,
            outputDestination: outputDestination.modelValue
        )
        let outputs = outputURLs.map { url in
            IntentFile(
                fileURL: url,
                filename: url.lastPathComponent,
                type: UTType(filenameExtension: url.pathExtension) ?? .data
            )
        }
        return .result(value: outputs)
    }
}

@MainActor
private enum ShortcutCompressionBridge {
    static func compress(
        _ urls: [URL],
        profileIdentifier: String,
        videoPresetOverride: VideoOutputPreset?,
        maximumVideoSizeMB: Int?,
        outputDestination: CompressionOutputDestination
    ) async throws -> [URL] {
        guard let model = AppModel.shared else { throw ShortcutIntentError.appUnavailable }
        return try await model.compressShortcutFiles(
            urls,
            profileIdentifier: profileIdentifier,
            videoPresetOverride: videoPresetOverride,
            maximumVideoSizeMB: maximumVideoSizeMB,
            outputDestination: outputDestination
        )
    }
}

private enum ShortcutIntentError: LocalizedError {
    case unavailableFiles
    case appUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailableFiles: return "快捷指令没有提供可访问的文件。"
        case .appUnavailable: return "DropSqueeze 尚未准备好，请重新运行快捷指令。"
        }
    }
}
