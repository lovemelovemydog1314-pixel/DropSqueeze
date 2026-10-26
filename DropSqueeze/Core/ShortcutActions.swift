import AppIntents
import UniformTypeIdentifiers

enum ShortcutVideoPreset: String, AppEnum {
    case compact10MB
    case share25MB
    case standard720p
    case high1080p

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "视频输出预设")

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

struct CompressMediaFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "压缩媒体文件"
    static var description = IntentDescription("为图片或视频生成更小的副本，并保留原文件。")
    static var openAppWhenRun = true

    @Parameter(
        title: "要压缩的文件",
        supportedTypeIdentifiers: ["public.image", "public.movie", "com.adobe.pdf"]
    )
    var files: [IntentFile]

    @Parameter(title: "视频输出预设", default: .standard720p)
    var videoPreset: ShortcutVideoPreset

    static var parameterSummary: some ParameterSummary {
        Summary("压缩 \(\.$files)，视频预设为 \(\.$videoPreset)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let inputURLs = files.compactMap(\.fileURL)
        guard inputURLs.count == files.count else {
            throw ShortcutIntentError.unavailableFiles
        }

        let outputURLs = try await ShortcutCompressionBridge.compress(
            inputURLs,
            videoPreset: videoPreset.outputPreset
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
    static func compress(_ urls: [URL], videoPreset: VideoOutputPreset) async throws -> [URL] {
        guard let model = AppModel.shared else { throw ShortcutIntentError.appUnavailable }
        return try await model.compressShortcutFiles(urls, videoPreset: videoPreset)
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
