import AVFoundation
import Foundation

private final class ExportSessionBox: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}

enum VideoTranscodingError: LocalizedError {
    case cannotCreateExport
    case exportFailed(String)
    case outputNotSmaller

    var errorDescription: String? {
        switch self {
        case .cannotCreateExport: return "此视频无法转码"
        case .exportFailed(let message): return message
        case .outputNotSmaller: return "转码结果没有更小，已保留原视频"
        }
    }
}

enum VideoTranscoder {
    static func transcodeToSmallerMP4(_ inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw VideoTranscodingError.cannotCreateExport
        }
        guard session.supportedFileTypes.contains(.mp4) else {
            throw VideoTranscodingError.exportFailed("此视频无法导出为 MP4")
        }

        let fileManager = FileManager.default
        let directory = inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let outputURL = uniqueOutputURL(in: directory, stem: stem)
        let temporaryURL = directory.appendingPathComponent(".dropsqueeze-\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        session.outputURL = temporaryURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let sessionBox = ExportSessionBox(session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch sessionBox.value.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: VideoTranscodingError.exportFailed("转码已取消"))
                case .failed:
                    continuation.resume(throwing: VideoTranscodingError.exportFailed(sessionBox.value.error?.localizedDescription ?? "视频转码失败"))
                default:
                    continuation.resume(throwing: VideoTranscodingError.exportFailed("视频转码未能完成"))
                }
            }
        }

        do {
            let sourceSize = try fileManager.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber
            let resultSize = try fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber
            guard let sourceSize, let resultSize, resultSize.intValue < sourceSize.intValue else {
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
