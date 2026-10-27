import AVFoundation
import Foundation

enum VideoCodecPreference: String, CaseIterable, Identifiable, Codable, Sendable, Equatable {
    case automatic
    case h264
    case hevc

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "自动"
        case .h264: return "H.264 · 兼容性优先"
        case .hevc: return "HEVC · 体积优先"
        }
    }
}

enum VideoFrameRate: Int, CaseIterable, Identifiable, Codable, Sendable, Equatable {
    case original = 0
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var title: String { rawValue == 0 ? "保持原帧率" : "最高 \(rawValue) fps" }
}

enum VideoBitrateTarget: Int, CaseIterable, Identifiable, Codable, Sendable, Equatable {
    case automatic = 0
    case economy = 1_500
    case balanced = 3_500
    case highQuality = 8_000

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .automatic: return "自动"
        case .economy: return "轻量 · 1.5 Mbps"
        case .balanced: return "均衡 · 3.5 Mbps"
        case .highQuality: return "清晰 · 8 Mbps"
        }
    }
}

enum VideoOutputPreset: String, CaseIterable, Identifiable, Codable, Sendable, Equatable {
    case compact10MB
    case share25MB
    case standard720p
    case high1080p

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact10MB: return "邮件 / Discord · ≤ 10 MB"
        case .share25MB: return "微信直发 · ≤ 25 MB"
        case .standard720p: return "标准 · 720p"
        case .high1080p: return "清晰 · 1080p"
        }
    }

    var detail: String {
        switch self {
        case .compact10MB: return "严格控制在 10 MB 以内，适合邮件附件与 Discord 免费上传。"
        case .share25MB: return "严格控制在微信 25 MB 文件限制之内，避免发送失败。"
        case .standard720p: return "720p 上限，不设文件大小上限。"
        case .high1080p: return "1080p 上限，不设文件大小上限。"
        }
    }

    fileprivate func exportPresetName(codec: VideoCodecPreference) -> String {
        if codec == .hevc {
            switch self {
            case .compact10MB, .share25MB: return AVAssetExportPresetHEVCHighestQuality
            case .standard720p, .high1080p: return AVAssetExportPresetHEVC1920x1080
            }
        }
        switch self {
        case .compact10MB: return AVAssetExportPreset640x480
        case .share25MB, .standard720p: return AVAssetExportPreset1280x720
        case .high1080p: return AVAssetExportPreset1920x1080
        }
    }

    fileprivate var fileLengthLimit: Int64? {
        switch self {
        case .compact10MB: return 9_800_000
        case .share25MB: return 24_500_000
        case .standard720p, .high1080p: return nil
        }
    }

    func exportAttempts(codec: VideoCodecPreference, needsSizeFallback: Bool) -> [String] {
        let first = exportPresetName(codec: codec)
        guard needsSizeFallback else { return [first] }
        let candidates: [String]
        if codec == .hevc {
            candidates = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPresetHEVCHighestQuality]
        } else {
            switch self {
            case .high1080p:
                candidates = [AVAssetExportPreset1280x720, AVAssetExportPreset640x480, AVAssetExportPresetLowQuality]
            case .standard720p, .share25MB:
                candidates = [AVAssetExportPreset640x480, AVAssetExportPresetLowQuality]
            case .compact10MB:
                candidates = [AVAssetExportPreset640x480, AVAssetExportPresetLowQuality]
            }
        }
        var result: [String] = []
        for name in [first] + candidates where !result.contains(name) {
            result.append(name)
        }
        return result
    }
}

struct VideoTrimRange: Sendable, Equatable {
    static let minimumDuration = 0.25

    let startSeconds: Double
    let endSeconds: Double

    var durationSeconds: Double { endSeconds - startSeconds }

    init(startSeconds: Double, endSeconds: Double, assetDurationSeconds: Double) throws {
        guard assetDurationSeconds.isFinite,
              assetDurationSeconds >= Self.minimumDuration,
              startSeconds.isFinite,
              endSeconds.isFinite,
              startSeconds >= 0,
              endSeconds <= assetDurationSeconds,
              endSeconds - startSeconds >= Self.minimumDuration else {
            throw VideoTrimRangeError.invalidRange
        }
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    func validate(against assetDurationSeconds: Double) throws {
        guard assetDurationSeconds.isFinite,
              assetDurationSeconds >= Self.minimumDuration,
              startSeconds.isFinite,
              endSeconds.isFinite,
              startSeconds >= 0,
              endSeconds <= assetDurationSeconds,
              durationSeconds >= Self.minimumDuration else {
            throw VideoTrimRangeError.invalidRange
        }
    }

    var timeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600)
        )
    }
}

enum VideoTrimRangeError: LocalizedError {
    case invalidRange

    var errorDescription: String? { "片段范围无效，请至少选择 0.25 秒且不要超出视频时长" }
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
    case invalidTrimRange

    var errorDescription: String? {
        switch self {
        case .cannotCreateExport: return "此视频无法转码"
        case .exportFailed(let message): return message
        case .outputNotSmaller: return "转码结果没有更小，已保留原视频"
        case .outputExceedsLimit: return "视频无法压到所选大小，请选择更大的目标体积"
        case .cancelled: return "视频压缩已取消"
        case .invalidTrimRange: return "剪辑片段范围无效，请重新选择"
        }
    }
}

enum VideoTranscoder {
    static func transcodeToSmallerMP4(
        _ inputURL: URL,
        preset: VideoOutputPreset = .standard720p,
        codec: VideoCodecPreference = .automatic,
        bitrateTarget: VideoBitrateTarget = .automatic,
        maximumFrameRate: VideoFrameRate = .original,
        includesAudio: Bool = true,
        maximumSizeMB: Int? = nil,
        trimRange: VideoTrimRange? = nil,
        requiresSmallerOutput: Bool = true,
        outputDirectory: URL? = nil,
        cancellation: VideoTranscoderCancellation? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let targetSizeMB = maximumSizeMB.flatMap { (1...5_000).contains($0) ? $0 : nil }
        let sourceAsset = AVURLAsset(url: inputURL)
        if let trimRange {
            let sourceDuration = try await sourceAsset.load(.duration).seconds
            do {
                try trimRange.validate(against: sourceDuration)
            } catch {
                throw VideoTranscodingError.invalidTrimRange
            }
        }
        let asset: AVAsset
        do {
            if includesAudio {
                asset = sourceAsset
            } else {
                asset = try await videoOnlyComposition(from: sourceAsset)
            }
        } catch {
            throw VideoTranscodingError.exportFailed("无法保留视频轨道：\(error.localizedDescription)")
        }
        let fileManager = FileManager.default
        let directory = outputDirectory ?? inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let outputURL = uniqueOutputURL(in: directory, stem: stem, suffix: trimRange == nil ? "compressed" : "edited")
        var fileLengthLimits = targetSizeMB == nil ? [preset.fileLengthLimit].compactMap { $0 } : []
        if let targetSizeMB {
            let maximumBytes = Int64(targetSizeMB) * 1_000_000
            fileLengthLimits.append(maximumBytes)
        }
        if bitrateTarget != .automatic, targetSizeMB == nil {
            let duration = try await asset.load(.duration)
            let seconds = trimRange?.durationSeconds ?? CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { throw VideoTranscodingError.cannotCreateExport }
            let desiredBytes = Double(bitrateTarget.rawValue) * 1_000 * seconds / 8
            guard desiredBytes < Double(Int64.max) else { throw VideoTranscodingError.cannotCreateExport }
            fileLengthLimits.append(Int64(desiredBytes.rounded(.down)))
        }
        let maximumFileLength = fileLengthLimits.min()
        let sourceSize = try fileManager.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber
        guard let sourceSize else { throw VideoTranscodingError.cannotCreateExport }
        let attemptNames = preset.exportAttempts(
            codec: codec,
            needsSizeFallback: maximumFileLength != nil
        )
        var lastExportError: Error?
        var foundOutputWithinLimit = false

        for (attemptIndex, presetName) in attemptNames.enumerated() {
            guard cancellation?.isCancelled != true else { throw VideoTranscodingError.cancelled }
            let isCompatible = await AVAssetExportSession.compatibility(
                ofExportPreset: presetName,
                with: asset,
                outputFileType: .mp4
            )
            guard isCompatible,
                  let session = AVAssetExportSession(asset: asset, presetName: presetName),
                  session.supportedFileTypes.contains(.mp4) else { continue }

            let temporaryURL = directory.appendingPathComponent(".dropsqueeze-\(UUID().uuidString).mp4")
            defer { try? fileManager.removeItem(at: temporaryURL) }
            session.outputURL = temporaryURL
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            if let trimRange { session.timeRange = trimRange.timeRange }
            if maximumFrameRate != .original {
                let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
                composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
                composition.frameDuration = CMTime(value: 1, timescale: Int32(maximumFrameRate.rawValue))
                session.videoComposition = composition
            }
            if let maximumFileLength { session.fileLengthLimit = maximumFileLength }

            let sessionBox = ExportSessionBox(session)
            cancellation?.attach(sessionBox)
            defer { cancellation?.detach(sessionBox) }
            do {
                try await export(sessionBox, attemptIndex: attemptIndex, attemptCount: attemptNames.count, onProgress: onProgress)
            } catch {
                if case VideoTranscodingError.cancelled = error { throw error }
                lastExportError = error
                continue
            }

            guard let resultSize = try fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber else {
                lastExportError = VideoTranscodingError.exportFailed("无法读取转码结果大小")
                continue
            }
            if let maximumFileLength, resultSize.int64Value > maximumFileLength {
                lastExportError = VideoTranscodingError.outputExceedsLimit
                continue
            }
            foundOutputWithinLimit = true
            guard !requiresSmallerOutput || resultSize.int64Value < sourceSize.int64Value else {
                lastExportError = VideoTranscodingError.outputNotSmaller
                continue
            }
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
            onProgress?(1)
            return outputURL
        }

        if foundOutputWithinLimit { throw VideoTranscodingError.outputNotSmaller }
        if maximumFileLength != nil { throw VideoTranscodingError.outputExceedsLimit }
        throw lastExportError ?? VideoTranscodingError.cannotCreateExport
    }

    private static func export(
        _ sessionBox: ExportSessionBox,
        attemptIndex: Int,
        attemptCount: Int,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        let session = sessionBox.value
        let progressTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let status = sessionBox.value.status
                if status == .completed || status == .failed || status == .cancelled { break }
                if status == .exporting {
                    let attemptProgress = Double(sessionBox.value.progress)
                    onProgress?((Double(attemptIndex) + attemptProgress) / Double(attemptCount))
                }
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
    }

    private static func videoOnlyComposition(from asset: AVAsset) async throws -> AVAsset {
        let composition = AVMutableComposition()
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw VideoTranscodingError.cannotCreateExport }
        for sourceTrack in videoTracks {
            let sourceTimeRange = try await sourceTrack.load(.timeRange)
            let preferredTransform = try await sourceTrack.load(.preferredTransform)
            guard let destinationTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw VideoTranscodingError.cannotCreateExport }
            try destinationTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: sourceTimeRange.start)
            destinationTrack.preferredTransform = preferredTransform
        }
        return composition
    }

    private static func uniqueOutputURL(in directory: URL, stem: String, suffix: String = "compressed") -> URL {
        let fileManager = FileManager.default
        var counter = 1
        var candidate = directory.appendingPathComponent("\(stem)-\(suffix).mp4")
        while fileManager.fileExists(atPath: candidate.path) {
            counter += 1
            candidate = directory.appendingPathComponent("\(stem)-\(suffix)-\(counter).mp4")
        }
        return candidate
    }
}

enum AudioExtractionError: LocalizedError {
    case noAudioTrack
    case cannotCreateExport
    case exportFailed(String)
    case invalidTrimRange
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "此视频没有可提取的音轨"
        case .cannotCreateExport: return "无法为此视频创建音频导出"
        case .exportFailed(let message): return message
        case .invalidTrimRange: return "音频片段范围无效，请重新选择"
        case .cancelled: return "音频导出已取消"
        }
    }
}

enum AudioExtractor {
    static func extractM4A(
        from inputURL: URL,
        trimRange: VideoTrimRange? = nil,
        cancellation: VideoTranscoderCancellation? = nil,
        outputDirectory: URL? = nil
    ) async throws -> URL {
        guard cancellation?.isCancelled != true else { throw AudioExtractionError.cancelled }
        let asset = AVURLAsset(url: inputURL)
        if let trimRange {
            let sourceDuration = try await asset.load(.duration).seconds
            do {
                try trimRange.validate(against: sourceDuration)
            } catch {
                throw AudioExtractionError.invalidTrimRange
            }
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AudioExtractionError.noAudioTrack
        }
        let preset = AVAssetExportPresetAppleM4A
        guard await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: .m4a),
              let session = AVAssetExportSession(asset: asset, presetName: preset),
              session.supportedFileTypes.contains(.m4a) else {
            throw AudioExtractionError.cannotCreateExport
        }

        let fileManager = FileManager.default
        let directory = outputDirectory ?? inputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isWritableFile(atPath: directory.path) else {
            throw AudioExtractionError.exportFailed("无法写入所选输出文件夹")
        }
        let temporaryURL = directory.appendingPathComponent(".dropsqueeze-\(UUID().uuidString).m4a")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        session.outputURL = temporaryURL
        session.outputFileType = .m4a
        session.shouldOptimizeForNetworkUse = true
        if let trimRange { session.timeRange = trimRange.timeRange }

        let sessionBox = ExportSessionBox(session)
        cancellation?.attach(sessionBox)
        defer { cancellation?.detach(sessionBox) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionBox.value.exportAsynchronously {
                switch sessionBox.value.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: AudioExtractionError.exportFailed(sessionBox.value.error?.localizedDescription ?? "音频导出失败"))
                case .cancelled:
                    continuation.resume(throwing: AudioExtractionError.cancelled)
                default:
                    continuation.resume(throwing: AudioExtractionError.exportFailed("音频导出未能完成"))
                }
            }
        }
        guard let outputSize = try fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber,
              outputSize.int64Value > 0 else {
            throw AudioExtractionError.exportFailed("音频导出文件为空")
        }

        let stem = inputURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(stem)-audio.m4a")
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-audio-\(number).m4a")
            number += 1
        }
        try fileManager.moveItem(at: temporaryURL, to: candidate)
        return candidate
    }
}
