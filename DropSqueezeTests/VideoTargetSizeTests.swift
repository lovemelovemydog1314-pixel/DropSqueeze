import AVFoundation
import CoreVideo
import XCTest
@testable import DropSqueeze

final class VideoTargetSizeTests: XCTestCase {
    func testSizeLimitedPresetsRetryWithLowerOutputPresets() {
        XCTAssertEqual(
            VideoOutputPreset.high1080p.exportAttempts(codec: .automatic, needsSizeFallback: true),
            [AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset640x480, AVAssetExportPresetLowQuality]
        )
        XCTAssertEqual(
            VideoOutputPreset.standard720p.exportAttempts(codec: .automatic, needsSizeFallback: true),
            [AVAssetExportPreset1280x720, AVAssetExportPreset640x480, AVAssetExportPresetLowQuality]
        )
        XCTAssertEqual(
            VideoOutputPreset.high1080p.exportAttempts(codec: .automatic, needsSizeFallback: false),
            [AVAssetExportPreset1920x1080]
        )
    }

    @MainActor
    func testCustomMaximumVideoSizePersistsAndInvalidValuesClearIt() {
        let suiteName = "DropSqueezeTests.video-target.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = RulesSettings(defaults: defaults)
        XCTAssertNil(settings.videoMaximumSizeMB)
        settings.setVideoMaximumSizeMB(42)
        XCTAssertEqual(settings.videoMaximumSizeMB, 42)
        XCTAssertEqual(RulesSettings(defaults: defaults).videoMaximumSizeMB, 42)

        settings.setVideoMaximumSizeMB(0)
        XCTAssertNil(settings.videoMaximumSizeMB)
        settings.setVideoMaximumSizeMB(5_001)
        XCTAssertNil(settings.videoMaximumSizeMB)
    }

    @MainActor
    func testSavedProfileKeepsCustomMaximumVideoSize() throws {
        let suiteName = "DropSqueezeTests.video-profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = RulesSettings(defaults: defaults)
        settings.setVideoMaximumSizeMB(18)
        let profile = try XCTUnwrap(settings.saveCurrentProfile(name: "邮件附件"))
        XCTAssertEqual(profile.videoMaximumSizeMB, 18)

        settings.setVideoMaximumSizeMB(nil)
        settings.apply(profile)
        XCTAssertEqual(settings.videoMaximumSizeMB, 18)

        let reopenedSettings = RulesSettings(defaults: defaults)
        XCTAssertEqual(reopenedSettings.savedProfiles.first?.videoMaximumSizeMB, 18)
    }

    @MainActor
    func testScenarioPresetsCoverEmailWebAndArchiveUseCases() {
        let suiteName = "DropSqueezeTests.scenarios.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RulesSettings(defaults: defaults)

        XCTAssertEqual(Set(CompressionScenario.allCases.map(\.id)).count, CompressionScenario.allCases.count)
        XCTAssertTrue(CompressionScenario.allCases.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })

        settings.setVideoMaximumSizeMB(42)
        settings.applyScenario(.emailAttachment)
        XCTAssertEqual(settings.imageResizePreset, .max1920)
        XCTAssertEqual(settings.imageFileOutputFormat, .jpeg)
        XCTAssertTrue(settings.stripImageMetadata)
        XCTAssertEqual(settings.videoOutputPreset, .compact10MB)
        XCTAssertEqual(settings.videoCodecPreference, .h264)
        XCTAssertNil(settings.videoMaximumSizeMB, "Applying a built-in preset must clear the prior custom cap.")

        settings.applyScenario(.webPublishing)
        XCTAssertEqual(settings.imageFileOutputFormat, .webP)
        XCTAssertTrue(settings.stripImageMetadata)
        XCTAssertEqual(settings.imageResizePreset, .max2560)
        XCTAssertEqual(CompressionScenario.webPublishing.requiredProFeature, .fileWebPOutput)
        XCTAssertNil(CompressionScenario.emailAttachment.requiredProFeature)

        settings.applyScenario(.archive)
        XCTAssertEqual(settings.imageResizePreset, .max4096)
        XCTAssertEqual(settings.imageQuality, 0.96, accuracy: 0.001)
        XCTAssertEqual(settings.imageFileOutputFormat, .original)
        XCTAssertFalse(settings.stripImageMetadata)
        XCTAssertEqual(settings.videoCodecPreference, .hevc)
        XCTAssertEqual(settings.videoOutputPreset, .high1080p)
        XCTAssertEqual(settings.videoFrameRate, .original)
    }

    func testTranscodeHonorsCustomMaximumAndPreservesSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-video-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("target-input.mp4")
        try makeTestVideo(at: inputURL, width: 1280, height: 720, frameCount: 120)
        let originalBytes = try Self.fileSize(at: inputURL)
        XCTAssertGreaterThan(originalBytes, 1_000_000, "Fixture must be large enough to exercise the custom cap.")

        let outputURL = try await VideoTranscoder.transcodeToSmallerMP4(
            inputURL,
            preset: .high1080p,
            codec: .automatic,
            bitrateTarget: .automatic,
            maximumFrameRate: .fps30,
            includesAudio: true,
            maximumSizeMB: 1,
            outputDirectory: directory
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path))
        XCTAssertEqual(try Self.fileSize(at: inputURL), originalBytes, "The source must remain byte-for-byte unchanged.")
        XCTAssertLessThan(try Self.fileSize(at: outputURL), 1_000_000)
        XCTAssertLessThan(try Self.fileSize(at: outputURL), originalBytes)

        let outputAsset = AVURLAsset(url: outputURL)
        let videoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let outputFrameRate = try await videoTracks[0].load(.nominalFrameRate)
        XCTAssertLessThanOrEqual(outputFrameRate, 30.1)
        let temporaryFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".dropsqueeze-") }
        XCTAssertTrue(temporaryFiles.isEmpty, "Failed and successful attempts must clean up temporary exports.")
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func makeTestVideo(at url: URL, width: Int, height: Int, frameCount: Int) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoMaxKeyFrameIntervalKey: 30
                ]
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else { throw VideoFixtureError.cannotCreateInput }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoFixtureError.cannotStartWriting }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            var pixelBuffer: CVPixelBuffer?
            let createStatus = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                &pixelBuffer
            )
            guard createStatus == kCVReturnSuccess, let pixelBuffer else { throw VideoFixtureError.cannotCreatePixelBuffer }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
                for y in 0..<height {
                    let rowOffset = y * bytesPerRow
                    for x in 0..<width {
                        let pixel = rowOffset + x * 4
                        let value = UInt8(truncatingIfNeeded: (x &* 73) ^ (y &* 151) ^ (frame &* 199) ^ ((x &* y) >> 3))
                        bytes[pixel] = value
                        bytes[pixel + 1] = value &+ UInt8(truncatingIfNeeded: x + frame)
                        bytes[pixel + 2] = value &+ UInt8(truncatingIfNeeded: y + frame * 3)
                        bytes[pixel + 3] = 255
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            let presentationTime = CMTime(value: Int64(frame), timescale: 30)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? VideoFixtureError.cannotAppendFrame
            }
        }

        input.markAsFinished()
        let finished = expectation(description: "fixture writer finishes")
        writer.finishWriting { finished.fulfill() }
        wait(for: [finished], timeout: 30)
        guard writer.status == .completed else { throw writer.error ?? VideoFixtureError.cannotFinishWriting }
    }

    private enum VideoFixtureError: Error {
        case cannotCreateInput
        case cannotStartWriting
        case cannotCreatePixelBuffer
        case cannotAppendFrame
        case cannotFinishWriting
    }
}
