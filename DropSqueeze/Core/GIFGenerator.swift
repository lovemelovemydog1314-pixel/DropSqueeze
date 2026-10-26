import AVFoundation
import CoreImage
import Foundation
import UniformTypeIdentifiers

private final class GIFVideoSource: @unchecked Sendable {
    let asset: AVAsset
    let track: AVAssetTrack
    let duration: CMTime
    let nominalFrameRate: Float
    let preferredTransform: CGAffineTransform

    init(
        asset: AVAsset,
        track: AVAssetTrack,
        duration: CMTime,
        nominalFrameRate: Float,
        preferredTransform: CGAffineTransform
    ) {
        self.asset = asset
        self.track = track
        self.duration = duration
        self.nominalFrameRate = nominalFrameRate
        self.preferredTransform = preferredTransform
    }
}

enum GIFGenerationError: LocalizedError {
    case noVideoTrack
    case tooLong
    case readerUnavailable(String)
    case noFrames
    case exportFailed
    case outputNotSmaller

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "视频没有可用画面"
        case .tooLong: return "GIF 转换仅支持 15 秒以内的视频片段"
        case .readerUnavailable(let message): return message
        case .noFrames: return "无法从视频读取画面"
        case .exportFailed: return "GIF 编码失败"
        case .outputNotSmaller: return "GIF 结果没有更小，已保留原视频"
        }
    }
}

enum GIFGenerator {
    private static let maximumFramesPerSecond = 30.0
    private static let maximumDuration = 15.0
    private static let maximumDimension = 1280.0

    static func generateSmallerGIF(from inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0, durationSeconds <= maximumDuration else {
            throw GIFGenerationError.tooLong
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GIFGenerationError.noVideoTrack
        }
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let preferredTransform = try await track.load(.preferredTransform)
        let source = GIFVideoSource(
            asset: asset,
            track: track,
            duration: duration,
            nominalFrameRate: nominalFrameRate,
            preferredTransform: preferredTransform
        )
        return try await Task.detached(priority: .utility) {
            try generateSynchronously(from: inputURL, source: source, durationSeconds: durationSeconds)
        }.value
    }

    private static func generateSynchronously(
        from inputURL: URL,
        source: GIFVideoSource,
        durationSeconds: Double
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory = inputURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".dropsqueeze-\(UUID().uuidString).gif")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let nominalFrameRate = Double(source.nominalFrameRate)
        let frameInterval = max(
            1.0 / maximumFramesPerSecond,
            1.0 / (nominalFrameRate.isFinite && nominalFrameRate > 0 ? nominalFrameRate : maximumFramesPerSecond)
        )
        let expectedFrameCount = max(1, Int(ceil(durationSeconds / frameInterval)))
        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            UTType.gif.identifier as CFString,
            expectedFrameCount,
            nil
        ) else { throw GIFGenerationError.exportFailed }

        let globalProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(destination, globalProperties as CFDictionary)

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: source.asset)
        } catch {
            throw GIFGenerationError.readerUnavailable(error.localizedDescription)
        }
        let output = AVAssetReaderTrackOutput(
            track: source.track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw GIFGenerationError.readerUnavailable("无法读取视频画面")
        }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: .zero, duration: source.duration)
        guard reader.startReading() else {
            throw GIFGenerationError.readerUnavailable(reader.error?.localizedDescription ?? "无法开始读取视频")
        }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        var nextFrameTime = 0.0
        var frameCount = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard presentationTime.isFinite else { continue }
            if presentationTime > maximumDuration { break }
            guard presentationTime + frameInterval / 2 >= nextFrameTime else { continue }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let didAddFrame = autoreleasepool { () -> Bool in
                let image = CIImage(cvPixelBuffer: pixelBuffer)
                    .transformed(by: source.preferredTransform)
                let extent = image.extent
                let normalized = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                let longestSide = max(normalized.extent.width, normalized.extent.height)
                let scale = min(1.0, maximumDimension / max(longestSide, 1))
                let resized = scale < 1
                    ? normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    : normalized
                guard let cgImage = context.createCGImage(resized, from: resized.extent) else { return false }
                let frameProperties: [CFString: Any] = [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: frameInterval,
                        kCGImagePropertyGIFUnclampedDelayTime: frameInterval
                    ]
                ]
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
                return true
            }

            if didAddFrame {
                frameCount += 1
                nextFrameTime += frameInterval
            }
            if frameCount >= expectedFrameCount { break }
        }

        guard frameCount > 0 else { throw GIFGenerationError.noFrames }
        guard CGImageDestinationFinalize(destination) else { throw GIFGenerationError.exportFailed }

        let sourceSize = try fileManager.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber
        let resultSize = try fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber
        guard let sourceSize, let resultSize, resultSize.intValue < sourceSize.intValue else {
            throw GIFGenerationError.outputNotSmaller
        }

        var suffix = 1
        while true {
            let name = suffix == 1
                ? "\(inputURL.deletingPathExtension().lastPathComponent)-compressed.gif"
                : "\(inputURL.deletingPathExtension().lastPathComponent)-compressed-\(suffix).gif"
            let outputURL = directory.appendingPathComponent(name)
            do {
                try fileManager.moveItem(at: temporaryURL, to: outputURL)
                return outputURL
            } catch {
                guard fileManager.fileExists(atPath: outputURL.path) else { throw error }
                suffix += 1
            }
        }
    }
}
