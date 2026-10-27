import AVFoundation
import AppKit
import CoreVideo
import PDFKit
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
        settings.set(.retinaDownscale, enabled: true)
        settings.set(.gifConversion, enabled: true)
        let profile = try XCTUnwrap(settings.saveCurrentProfile(name: "邮件附件"))
        XCTAssertEqual(profile.videoMaximumSizeMB, 18)
        XCTAssertEqual(profile.retinaDownscaleEnabled, true)
        XCTAssertEqual(profile.gifConversionEnabled, true)

        settings.setVideoMaximumSizeMB(nil)
        settings.set(.retinaDownscale, enabled: false)
        settings.set(.gifConversion, enabled: false)
        settings.apply(profile)
        XCTAssertEqual(settings.videoMaximumSizeMB, 18)
        XCTAssertTrue(settings.retinaDownscaleEnabled)
        XCTAssertTrue(settings.gifConversionEnabled)

        let reopenedSettings = RulesSettings(defaults: defaults)
        XCTAssertEqual(reopenedSettings.savedProfiles.first?.videoMaximumSizeMB, 18)
        XCTAssertEqual(reopenedSettings.savedProfiles.first?.retinaDownscaleEnabled, true)
        XCTAssertEqual(reopenedSettings.savedProfiles.first?.gifConversionEnabled, true)
    }

    func testLegacySavedProfileWithoutNewOptionalFieldsStillDecodes() throws {
        let oldProfile = SavedCompressionProfile(
            name: "旧配置",
            imageResizePreset: .max1920,
            imageQuality: 0.8,
            imageFileOutputFormat: .jpeg,
            stripImageMetadata: true,
            videoOutputPreset: .standard720p,
            videoCodecPreference: .automatic,
            videoBitrateTarget: .balanced,
            videoFrameRate: .original,
            videoIncludesAudio: true
        )
        let encoded = try PropertyListEncoder().encode(oldProfile)
        var legacyDictionary = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any]
        )
        legacyDictionary.removeValue(forKey: "videoMaximumSizeMB")
        legacyDictionary.removeValue(forKey: "retinaDownscaleEnabled")
        legacyDictionary.removeValue(forKey: "gifConversionEnabled")
        let legacyData = try PropertyListSerialization.data(fromPropertyList: legacyDictionary, format: .binary, options: 0)

        let decoded = try PropertyListDecoder().decode(SavedCompressionProfile.self, from: legacyData)
        XCTAssertEqual(decoded.name, "旧配置")
        XCTAssertNil(decoded.videoMaximumSizeMB)
        XCTAssertNil(decoded.retinaDownscaleEnabled)
        XCTAssertNil(decoded.gifConversionEnabled)
    }

    @MainActor
    func testShortcutProfileReferencesResolveBuiltInsAndSavedProfiles() throws {
        let scenarioIdentifier = CompressionProfileReference.identifier(for: .emailAttachment)
        let scenarioProfile = try XCTUnwrap(
            CompressionProfileReference.resolve(scenarioIdentifier, savedProfiles: [])
        )
        XCTAssertEqual(scenarioProfile.name, "邮件附件")
        XCTAssertEqual(scenarioProfile.videoMaximumSizeMB, nil)

        let suiteName = "DropSqueezeTests.shortcut-profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RulesSettings(defaults: defaults)
        let savedProfile = try XCTUnwrap(settings.saveCurrentProfile(name: "我的分享配置"))
        let savedIdentifier = CompressionProfileReference.identifier(for: savedProfile)
        XCTAssertEqual(
            CompressionProfileReference.resolve(savedIdentifier, savedProfiles: [savedProfile])?.id,
            savedProfile.id
        )
        XCTAssertNil(CompressionProfileReference.resolve("saved:not-a-uuid", savedProfiles: [savedProfile]))
        XCTAssertTrue(CompressionProfileReference.isCurrent(CompressionProfileReference.currentIdentifier))
    }

    func testShortcutProfileQueryOffersCurrentAndScenarioChoices() async throws {
        let query = ShortcutCompressionProfileQuery()
        let suggestions = try await query.suggestedEntities()
        let identifiers = Set(suggestions.map(\.id))
        XCTAssertTrue(identifiers.contains(CompressionProfileReference.currentIdentifier))
        XCTAssertTrue(identifiers.contains(CompressionProfileReference.identifier(for: .emailAttachment)))
        XCTAssertTrue(identifiers.contains(CompressionProfileReference.identifier(for: .webPublishing)))

        let selected = try await query.entities(for: [CompressionProfileReference.identifier(for: .emailAttachment)])
        XCTAssertEqual(selected.map(\.id), [CompressionProfileReference.identifier(for: .emailAttachment)])
    }

    func testShortcutOutputDestinationSelectsConfiguredOrSourceFolder() {
        let sourceURL = URL(fileURLWithPath: "/tmp/incoming/clip.mov")
        let configuredFolder = URL(fileURLWithPath: "/tmp/compressed", isDirectory: true)
        XCTAssertEqual(
            CompressionOutputDestination.appDefault.resolveDirectory(
                configuredOutputFolder: configuredFolder,
                sourceURL: sourceURL
            ),
            configuredFolder
        )
        XCTAssertEqual(
            CompressionOutputDestination.sameAsSource.resolveDirectory(
                configuredOutputFolder: configuredFolder,
                sourceURL: sourceURL
            ),
            sourceURL.deletingLastPathComponent()
        )
        XCTAssertEqual(
            CompressionOutputDestination.appDefault.resolveDirectory(configuredOutputFolder: nil, sourceURL: sourceURL),
            sourceURL.deletingLastPathComponent()
        )
    }

    func testFolderRulesKeepLegacyDefaultsAndResolveIndependentProfiles() throws {
        let legacyRule = FolderWatchRule(
            scope: .videos,
            includeSubfolders: true,
            filenameContains: "recording",
            maximumFileSizeMB: 80,
            outputNameTemplate: "{name}-{date}"
        )
        let legacyEncoded = try PropertyListEncoder().encode(legacyRule)
        var legacyDictionary = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: legacyEncoded, format: nil) as? [String: Any]
        )
        legacyDictionary.removeValue(forKey: "compressionProfileIdentifier")
        let legacyData = try PropertyListSerialization.data(fromPropertyList: legacyDictionary, format: .binary, options: 0)
        let migratedRule = try PropertyListDecoder().decode(FolderWatchRule.self, from: legacyData)
        XCTAssertTrue(migratedRule.usesCurrentCompressionProfile)
        XCTAssertEqual(migratedRule.scope, .videos)
        XCTAssertTrue(migratedRule.includeSubfolders)
        XCTAssertEqual(migratedRule.maximumFileSizeMB, 80)

        let savedProfile = SavedCompressionProfile(
            name: "窄带视频",
            imageResizePreset: .max1920,
            imageQuality: 0.75,
            imageFileOutputFormat: .jpeg,
            stripImageMetadata: true,
            videoOutputPreset: .compact10MB,
            videoCodecPreference: .h264,
            videoBitrateTarget: .economy,
            videoFrameRate: .fps30,
            videoIncludesAudio: true,
            videoMaximumSizeMB: 8
        )
        let profiles = [savedProfile]
        let videoFolderRule = FolderWatchRule(
            scope: .videos,
            compressionProfileIdentifier: CompressionProfileReference.identifier(for: savedProfile)
        )
        let imageFolderRule = FolderWatchRule(
            scope: .images,
            compressionProfileIdentifier: CompressionProfileReference.identifier(for: .webPublishing)
        )

        XCTAssertFalse(videoFolderRule.usesCurrentCompressionProfile)
        XCTAssertEqual(videoFolderRule.resolvedCompressionProfile(savedProfiles: profiles)?.videoMaximumSizeMB, 8)
        XCTAssertEqual(imageFolderRule.resolvedCompressionProfile(savedProfiles: profiles)?.imageFileOutputFormat, .webP)
        XCTAssertNil(videoFolderRule.resolvedCompressionProfile(savedProfiles: []), "Deleted profiles must not silently select another profile.")

        let roundTrip = try PropertyListDecoder().decode(
            FolderWatchRule.self,
            from: PropertyListEncoder().encode(videoFolderRule)
        )
        XCTAssertEqual(roundTrip, videoFolderRule)
    }

    func testHistoryItemFromBeforeTechnicalDetailsStillDecodes() throws {
        let legacyItem = HistoryItem(
            name: "old.png",
            kind: .imageFile,
            originalBytes: 100,
            resultBytes: 50
        )
        let encoded = try PropertyListEncoder().encode(legacyItem)
        var legacyDictionary = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any]
        )
        legacyDictionary.removeValue(forKey: "sourceDetails")
        legacyDictionary.removeValue(forKey: "outputDetails")
        let legacyData = try PropertyListSerialization.data(fromPropertyList: legacyDictionary, format: .binary, options: 0)

        let decoded = try PropertyListDecoder().decode(HistoryItem.self, from: legacyData)
        XCTAssertEqual(decoded.name, "old.png")
        XCTAssertNil(decoded.sourceDetails)
        XCTAssertNil(decoded.outputDetails)
    }

    func testImageTechnicalDetailsReportActualFormatAndDimensions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-image-details-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("details.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 37,
            pixelsHigh: 19,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let imageData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try imageData.write(to: imageURL)

        let optionalDetails = await MediaTechnicalDetails.read(from: imageURL, kind: .imageFile)
        let details = try XCTUnwrap(optionalDetails)
        XCTAssertEqual(details.format, "PNG")
        XCTAssertEqual(details.width, 37)
        XCTAssertEqual(details.height, 19)
        XCTAssertTrue(details.summary.contains("PNG"))
        XCTAssertTrue(details.summary.contains("37 × 19"))

        let historyItem = HistoryItem(
            name: "details.png",
            kind: .imageFile,
            originalBytes: Int64(imageData.count),
            resultBytes: Int64(imageData.count / 2),
            sourceDetails: details,
            outputDetails: details
        )
        let restoredItem = try PropertyListDecoder().decode(
            HistoryItem.self,
            from: PropertyListEncoder().encode(historyItem)
        )
        XCTAssertEqual(restoredItem.sourceDetails, details)
        XCTAssertEqual(restoredItem.outputDetails, details)
    }

    func testPDFTechnicalDetailsReportPageCount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-pdf-details-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdfURL = directory.appendingPathComponent("details.pdf")

        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 24,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let image = NSImage(size: NSSize(width: 32, height: 24))
        image.addRepresentation(bitmap)
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 1)
        try XCTUnwrap(document.dataRepresentation()).write(to: pdfURL)

        let optionalDetails = await awaitDetails(from: pdfURL, kind: .pdfFile)
        let details = try XCTUnwrap(optionalDetails)
        XCTAssertEqual(details.format, "PDF")
        XCTAssertEqual(details.pageCount, 2)
        XCTAssertTrue(details.summary.contains("2 页"))
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
        let optionalSourceDetails = await MediaTechnicalDetails.read(from: inputURL, kind: .videoFile)
        let sourceDetails = try XCTUnwrap(optionalSourceDetails)
        XCTAssertEqual(sourceDetails.width, 1280)
        XCTAssertEqual(sourceDetails.height, 720)
        XCTAssertEqual(sourceDetails.videoCodec, "H.264")
        XCTAssertEqual(sourceDetails.audioTrackCount, 0)

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
        let optionalOutputDetails = await MediaTechnicalDetails.read(from: outputURL, kind: .videoFile)
        let outputDetails = try XCTUnwrap(optionalOutputDetails)
        XCTAssertNotNil(outputDetails.width)
        XCTAssertNotNil(outputDetails.height)
        XCTAssertEqual(outputDetails.videoCodec, "H.264")
        XCTAssertEqual(outputDetails.audioTrackCount, 0)
        let temporaryFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".dropsqueeze-") }
        XCTAssertTrue(temporaryFiles.isEmpty, "Failed and successful attempts must clean up temporary exports.")
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func awaitDetails(from url: URL, kind: HistoryItem.Kind) async -> MediaTechnicalDetails? {
        await MediaTechnicalDetails.read(from: url, kind: kind)
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

    @MainActor
    func testPlatformHardCapPresetsHaveSafeHeadroom() {
        XCTAssertTrue(VideoOutputPreset.share25MB.title.contains("微信直发"))
        XCTAssertTrue(VideoOutputPreset.compact10MB.title.contains("10 MB"))
        XCTAssertTrue(CompressionScenario.weChat.title.contains("微信直发"))
        XCTAssertTrue(CompressionScenario.silentTutorial.title.contains("静音"))

        let weChatProfile = CompressionScenario.weChat.profile
        XCTAssertEqual(weChatProfile.videoOutputPreset, .share25MB)
        XCTAssertEqual(weChatProfile.videoMaximumSizeMB, 24)
        XCTAssertTrue(weChatProfile.videoIncludesAudio)

        let silentProfile = CompressionScenario.silentTutorial.profile
        XCTAssertFalse(silentProfile.videoIncludesAudio)
    }

    @MainActor
    func testCompletionSoundAndHapticsPreferencesPersist() {
        let suiteName = "DropSqueezeTests.feedback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = RulesSettings(defaults: defaults)
        XCTAssertTrue(settings.completionSoundEnabled)
        XCTAssertEqual(settings.completionSoundName, CompressionFeedbackSound.pop.rawValue)
        XCTAssertTrue(settings.hapticFeedbackEnabled)

        settings.setCompletionSoundEnabled(false)
        settings.setCompletionSoundName(CompressionFeedbackSound.glass.rawValue)
        settings.setHapticFeedbackEnabled(false)

        let reloaded = RulesSettings(defaults: defaults)
        XCTAssertFalse(reloaded.completionSoundEnabled)
        XCTAssertEqual(reloaded.completionSoundName, CompressionFeedbackSound.glass.rawValue)
        XCTAssertFalse(reloaded.hapticFeedbackEnabled)

        CompressionFeedbackController.shared.playFeedback(soundName: "None", haptics: false)
        CompressionFeedbackController.shared.playFeedback(soundName: "Pop", haptics: true)
    }

    func testVideoAudioStrippingOptionProducesVideoWithoutAudioTracks() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-video-mute-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("mute-input.mp4")
        try makeTestVideo(at: inputURL, width: 640, height: 360, frameCount: 60)

        let outputURL = try await VideoTranscoder.transcodeToSmallerMP4(
            inputURL,
            preset: .standard720p,
            codec: .automatic,
            bitrateTarget: .automatic,
            maximumFrameRate: .fps30,
            includesAudio: false,
            maximumSizeMB: nil,
            outputDirectory: directory
        )

        let outputAsset = AVURLAsset(url: outputURL)
        let audioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audioTracks.isEmpty, "When includesAudio is false, output video must have 0 audio tracks.")
    }

    private enum VideoFixtureError: Error {
        case cannotCreateInput
        case cannotStartWriting
        case cannotCreatePixelBuffer
        case cannotAppendFrame
        case cannotFinishWriting
    }
}
