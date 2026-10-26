import AVFoundation
import Foundation

enum VideoOutputPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case compact10MB
    case share25MB
    case standard720p
    case high1080p

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact10MB: return "小体积 · 最多 10 MB"
        case .share25MB: return "分享 · 最多 25 MB"
        case .standard720p: return "标准 · 720p"
        case .high1080p: return "清晰 · 1080p"
        }
    }

    var detail: String {
        switch self {
        case .compact10MB: return "适合邮件和小附件；输出不超过 10 MB。"
        case .share25MB: return "适合聊天和常见分享；输出不超过 25 MB。"
        case .standard720p: return "720p 上限，不设文件大小上限。"
        case .high1080p: return "1080p 上限，不设文件大小上限。"
        }
    }

    fileprivate var exportPresetName: String {
        switch self {
        case .compact10MB: return AVAssetExportPreset640x480
        case .share25MB, .standard720p: return AVAssetExportPreset1280x720
        case .high1080p: return AVAssetExportPreset1920x1080
        }
    }

    fileprivate var fileLengthLimit: Int64? {
        switch self {
        case .compact10MB: return 10_000_000
        case .share25MB: return 25_000_000
        case .standard720p, .high1080p: return nil
        }
    }
}

final class ExportSessionBox: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}

final class VideoTranscoderCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var sessionBox: ExportSessionBox?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ sessionBox: ExportSessionBox) {
        lock.lock()
        self.sessionBox = sessionBox
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { sessionBox.value.cancelExport() }
    }

    func detach(_ sessionBox: ExportSessionBox) {
        lock.lock()
        if self.sessionBox === sessionBox { self.sessionBox = nil }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let sessionBox = self.sessionBox
        lock.unlock()
        sessionBox?.value.cancelExport()
    }
}

enum VideoTranscodingError: LocalizedError {
    case cannotCreateExport
    case exportFailed(String)
    case outputNotSmaller
    case outputExceedsLimit
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cannotCreateExport: return "此视频无法转码"
        case .exportFailed(let message): return message
        case .outputNotSmaller: return "转码结果没有更小，已保留原视频"
        case .outputExceedsLimit: return "视频无法压到所选大小，请选择更大的目标体积"
        case .cancelled: return "视频压缩已取消"
        }
    }
}

enum VideoTranscoder {
    static func transcodeToSmallerMP4(
        _ inputURL: URL,
        preset: VideoOutputPreset = .standard720p,
        outputDirectory: URL? = nil,
        cancellation: VideoTranscoderCancellation? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset.exportPresetName) else {
            throw VideoTranscodingError.cannotCreateExport
        }
        guard session.supportedFileTypes.contains(.mp4) else {
            throw VideoTranscodingError.exportFailed("此视频无法导出为 MP4")
        }

        let fileManager = FileManager.default
        let directory = outputDirectory ?? inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let outputURL = uniqueOutputURL(in: directory, stem: stem)
        let temporaryURL = directory.appendingPathComponent(".dropsqueeze-\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        session.outputURL = temporaryURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if let fileLengthLimit = preset.fileLengthLimit {
            session.fileLengthLimit = fileLengthLimit
        }

        let sessionBox = ExportSessionBox(session)
        cancellation?.attach(sessionBox)
        defer { cancellation?.detach(sessionBox) }
        guard cancellation?.isCancelled != true else { throw VideoTranscodingError.cancelled }

        let progressTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let status = sessionBox.value.status
                if status == .completed || status == .failed || status == .cancelled { break }
                if status == .exporting { onProgress?(Double(sessionBox.value.progress)) }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.exportAsynchronously {
                    switch sessionBox.value.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: VideoTranscodingError.cancelled)
                    case .failed:
                        continuation.resume(throwing: VideoTranscodingError.exportFailed(sessionBox.value.error?.localizedDescription ?? "视频转码失败"))
                    default:
                        continuation.resume(throwing: VideoTranscodingError.exportFailed("视频转码未能完成"))
                    }
                }
            }
            progressTask.cancel()
            await progressTask.value
        } catch {
            progressTask.cancel()
            await progressTask.value
            throw error
        }
        onProgress?(1)

        do {
            let sourceSize = try fileManager.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber
            let resultSize = try fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber
            if let fileLengthLimit = preset.fileLengthLimit,
               let resultSize,
               resultSize.int64Value > fileLengthLimit {
                try? fileManager.removeItem(at: temporaryURL)
                throw VideoTranscodingError.outputExceedsLimit
            }
            guard let sourceSize, let resultSize, resultSize.int64Value < sourceSize.int64Value else {
                try? fileManager.removeItem(at: temporaryURL)
                throw VideoTranscodingError.outputNotSmaller
            }
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
            return outputURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func uniqueOutputURL(in directory: URL, stem: String) -> URL {
        let fileManager = FileManager.default
        var suffix = 1
        var candidate = directory.appendingPathComponent("\(stem)-compressed.mp4")
        while fileManager.fileExists(atPath: candidate.path) {
            suffix += 1
            candidate = directory.appendingPathComponent("\(stem)-compressed-\(suffix).mp4")
        }
        return candidate
    }
}
