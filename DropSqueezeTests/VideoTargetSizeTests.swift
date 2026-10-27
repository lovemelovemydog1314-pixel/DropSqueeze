import AVFoundation
import AppKit
import CoreVideo
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
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
    func testCustomMaximumImageSizePersistsAndInvalidValuesClearIt() throws {
        let suiteName = "DropSqueezeTests.image-target.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = RulesSettings(defaults: defaults)
        XCTAssertNil(settings.imageMaximumSizeMB)
        settings.setImageMaximumSizeMB(0.7)
        XCTAssertEqual(settings.imageMaximumSizeMB, 0.7)
        XCTAssertEqual(RulesSettings(defaults: defaults).imageMaximumSizeMB, 0.7)

        let profile = try XCTUnwrap(settings.saveCurrentProfile(name: "小图分享"))
        XCTAssertEqual(profile.imageMaximumSizeMB, 0.7)
        settings.setImageMaximumSizeMB(nil)
        settings.apply(profile)
        XCTAssertEqual(settings.imageMaximumSizeMB, 0.7)
        XCTAssertEqual(RulesSettings(defaults: defaults).savedProfiles.first?.imageMaximumSizeMB, 0.7)

        settings.setImageMaximumSizeMB(0.05)
        XCTAssertNil(settings.imageMaximumSizeMB)
        settings.setImageMaximumSizeMB(5_001)
        XCTAssertNil(settings.imageMaximumSizeMB)
        XCTAssertNil(ImageOutputSizeLimit.bytes(for: .nan))
        XCTAssertNil(ImageOutputSizeLimit.bytes(for: .infinity))
    }

    func testImageOutputSizeLimitsConvertDecimalMegabytesSafely() {
        XCTAssertEqual(ImageOutputSizeLimit.bytes(for: 0.1), 100_000)
        XCTAssertEqual(ImageOutputSizeLimit.bytes(for: 1.25), 1_250_000)
        XCTAssertNil(ImageOutputSizeLimit.bytes(for: 0.099))
        XCTAssertNil(ImageOutputSizeLimit.bytes(for: 5_000.1))
    }

    func testImageCompressionRejectsAnInvalidTargetSize() throws {
        let sourceData = try makeNoisePNG(width: 10, height: 10)
        let options = ImageCompressionOptions(
            resizeRetinaTo1x: false,
            outputWebP: false,
            outputTypeIdentifier: UTType.jpeg.identifier,
            maxPixelDimension: nil,
            jpegQuality: 0.88,
            stripMetadata: true,
            maximumOutputSizeMB: 0.05
        )

        XCTAssertThrowsError(try ImageCompressor.compress(
            data: sourceData,
            typeIdentifier: UTType.png.identifier,
            options: options
        )) { error in
            XCTAssertEqual((error as? ImageCompressionError)?.errorDescription, "图片体积上限需要设置为 0.1–5000 MB")
        }
    }

    func testImageCompressionResizesAndTunesQualityToMeetTheRequestedMaximum() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-image-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("noise.png")
        let sourceData = try makeNoisePNG(width: 1_024, height: 768)
        try sourceData.write(to: inputURL)
        let options = ImageCompressionOptions(
            resizeRetinaTo1x: false,
            outputWebP: false,
            outputTypeIdentifier: UTType.jpeg.identifier,
            maxPixelDimension: nil,
            jpegQuality: 0.92,
            stripMetadata: true,
            maximumOutputSizeMB: 0.2
        )

        let compressed = try XCTUnwrap(ImageCompressor.compressFile(at: inputURL, options: options))
        XCTAssertLessThanOrEqual(compressed.data.count, 200_000)
        XCTAssertEqual(compressed.typeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(try Data(contentsOf: inputURL), sourceData, "Target-size compression must leave the original untouched.")

        let outputURL = try ImageCompressor.writeCompressedFile(compressed, beside: inputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertLessThanOrEqual(try Self.fileSize(at: outputURL), 200_000)
        XCTAssertEqual(try Data(contentsOf: inputURL), sourceData)
    }

    func testImageTargetSizeCanShrinkLosslessPNGWithoutChangingItsFormat() throws {
        let sourceData = try makeNoisePNG(width: 1_024, height: 768)
        let options = ImageCompressionOptions(
            resizeRetinaTo1x: false,
            outputWebP: false,
            outputTypeIdentifier: UTType.png.identifier,
            maxPixelDimension: nil,
            jpegQuality: 0.88,
            stripMetadata: true,
            maximumOutputSizeMB: 0.1
        )

        let compressed = try XCTUnwrap(ImageCompressor.compress(data: sourceData, typeIdentifier: UTType.png.identifier, options: options))
        XCTAssertLessThanOrEqual(compressed.data.count, 100_000)
        XCTAssertEqual(compressed.typeIdentifier, UTType.png.identifier)
        let resultSource = try XCTUnwrap(CGImageSourceCreateWithData(compressed.data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(resultSource, 0, nil) as? [CFString: Any])
        let longestEdge = max(
            try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
            try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        )
        XCTAssertLessThan(longestEdge, 1_024)
    }

    func testBatchScannerRecursivelyIncludesSupportedFilesAndDeduplicatesInputs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-batch-scan-\(UUID().uuidString)", isDirectory: true)
        let nestedDirectory = directory.appendingPathComponent("nested", isDirectory: true)
        let hiddenDirectory = directory.appendingPathComponent(".hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("image.png")
        let pdfURL = nestedDirectory.appendingPathComponent("document.pdf")
        let unsupportedURL = nestedDirectory.appendingPathComponent("notes.txt")
        let hiddenURL = hiddenDirectory.appendingPathComponent("secret.jpg")
        for url in [imageURL, pdfURL, unsupportedURL, hiddenURL] { try Data([1]).write(to: url) }

        let expanded = BatchMediaFileScanner.expand([directory, directory])
        XCTAssertEqual(Set(expanded.map { $0.url.standardizedFileURL.path }), Set([imageURL.path, pdfURL.path]))
        XCTAssertTrue(expanded.allSatisfy { $0.securityScopeURL.standardizedFileURL == directory.standardizedFileURL })
        XCTAssertEqual(BatchMediaFileScanner.expand([directory], maximumFiles: 1).count, 1)
        XCTAssertTrue(BatchMediaFileScanner.expand([directory], maximumFiles: 0).isEmpty)
        XCTAssertFalse(BatchMediaFileScanner.isSupported(unsupportedURL))
    }

    @MainActor
    func testClipboardCollectionPreferenceIsOptInAndPersists() {
        let suiteName = "DropSqueezeTests.clipboard-collection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = RulesSettings(defaults: defaults)
        XCTAssertFalse(settings.clipboardCollectionEnabled)
        settings.setClipboardCollectionEnabled(true)
        XCTAssertTrue(RulesSettings(defaults: defaults).clipboardCollectionEnabled)
        settings.setClipboardCollectionEnabled(false)
        XCTAssertFalse(RulesSettings(defaults: defaults).clipboardCollectionEnabled)
    }

    @MainActor
    func testAutomationWorkflowRecipesPersistUpdateValidateAndDelete() throws {
        let suiteName = "DropSqueezeTests.workflow-recipes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = RulesSettings(defaults: defaults)
        XCTAssertTrue(settings.automationRecipes.isEmpty)
        var rule = FolderWatchRule(
            scope: .images,
            includeSubfolders: true,
            filenameContains: "  screenshot  ",
            maximumFileSizeMB: 250,
            outputNameTemplate: "{name}-{date}",
            compressionProfileIdentifier: CompressionProfileReference.identifier(for: .emailAttachment)
        )
        let recipe = try XCTUnwrap(settings.saveAutomationRecipe(name: "  客户端截图  ", rule: rule))
        XCTAssertEqual(recipe.name, "客户端截图")
        XCTAssertEqual(recipe.rule.filenameContains, "screenshot")
        XCTAssertTrue(recipe.isAvailable(savedProfiles: settings.savedProfiles))
        XCTAssertTrue(recipe.summary(savedProfiles: settings.savedProfiles).contains("250 MB"))

        let reloaded = RulesSettings(defaults: defaults)
        XCTAssertEqual(reloaded.automationRecipes, [recipe])

        rule.scope = .videos
        rule.includeSubfolders = false
        rule.maximumFileSizeMB = 80
        let updated = try XCTUnwrap(settings.saveAutomationRecipe(name: "客户端截图", rule: rule))
        XCTAssertEqual(updated.id, recipe.id, "Saving a recipe with the same name should update it in place.")
        XCTAssertEqual(settings.automationRecipes.count, 1)
        XCTAssertEqual(RulesSettings(defaults: defaults).automationRecipes.first?.rule.scope, .videos)

        XCTAssertNil(settings.saveAutomationRecipe(name: "   ", rule: rule))
        XCTAssertNil(settings.saveAutomationRecipe(name: String(repeating: "长", count: 41), rule: rule))
        var invalidProfileRule = rule
        invalidProfileRule.compressionProfileIdentifier = "saved:deleted-profile"
        XCTAssertNil(settings.saveAutomationRecipe(name: "失效配置", rule: invalidProfileRule))
        var invalidSizeRule = rule
        invalidSizeRule.maximumFileSizeMB = 0
        XCTAssertNil(settings.saveAutomationRecipe(name: "非法体积", rule: invalidSizeRule))

        settings.deleteAutomationRecipe(recipe.id)
        XCTAssertTrue(settings.automationRecipes.isEmpty)
        XCTAssertTrue(RulesSettings(defaults: defaults).automationRecipes.isEmpty)
    }

    @MainActor
    func testAutomationWorkflowRecipesHaveBoundedLibrary() {
        let suiteName = "DropSqueezeTests.workflow-recipes-limit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = RulesSettings(defaults: defaults)
        for index in 0..<RulesSettings.maximumAutomationRecipeCount {
            XCTAssertNotNil(settings.saveAutomationRecipe(name: "流程 \(index)", rule: FolderWatchRule()))
        }
        XCTAssertEqual(settings.automationRecipes.count, RulesSettings.maximumAutomationRecipeCount)
        XCTAssertNil(settings.saveAutomationRecipe(name: "额外流程", rule: FolderWatchRule()))
        XCTAssertNotNil(settings.saveAutomationRecipe(name: "流程 0", rule: FolderWatchRule(scope: .videos)))
        XCTAssertEqual(settings.automationRecipes.count, RulesSettings.maximumAutomationRecipeCount)
    }

    func testClipboardCollectionBufferKeepsRecentUniqueFileCopiesAndCanClear() {
        var buffer = ClipboardCollectionBuffer()
        let fileA = URL(fileURLWithPath: "/tmp/collection-a.png")
        let fileB = URL(fileURLWithPath: "/tmp/collection-b.png")
        XCTAssertTrue(buffer.append(.files(urls: [fileA, fileA, fileB], changeCount: 1)))
        XCTAssertEqual(buffer.items.count, 1)
        guard case .files(let urls) = buffer.items[0].content else {
            XCTFail("The clipboard collection should retain copied file URLs.")
            return
        }
        XCTAssertEqual(urls, [fileA, fileB])
        XCTAssertFalse(buffer.append(.files(urls: [fileA, fileB], changeCount: 2)), "Identical file copies should not create duplicate cards.")

        for index in 0..<(ClipboardCollectionBuffer.maximumItemCount + 3) {
            let url = URL(fileURLWithPath: "/tmp/collection-\(index).png")
            XCTAssertTrue(buffer.append(.files(urls: [url], changeCount: index + 3)))
        }
        XCTAssertEqual(buffer.items.count, ClipboardCollectionBuffer.maximumItemCount)
        XCTAssertEqual(buffer.items.first?.displayName, "collection-14.png")
        XCTAssertEqual(buffer.items.last?.displayName, "collection-3.png")
        let removedID = try! XCTUnwrap(buffer.items.first?.id)
        buffer.remove(id: removedID)
        XCTAssertEqual(buffer.items.count, ClipboardCollectionBuffer.maximumItemCount - 1)
        buffer.clear()
        XCTAssertTrue(buffer.items.isEmpty)
    }

    func testClipboardCollectionBufferCapsImageMemoryAndRestoresClipboardTypes() throws {
        var buffer = ClipboardCollectionBuffer()
        let imageType = UTType.png.identifier
        for index in 0..<5 {
            let data = Data(repeating: UInt8(index + 1), count: 9 * 1_024 * 1_024)
            XCTAssertTrue(buffer.append(.image(data: data, typeIdentifier: imageType, changeCount: index)))
        }
        XCTAssertEqual(buffer.items.count, 4)
        XCTAssertEqual(buffer.items.first?.imageData?.first, 5)
        let rejected = Data(repeating: 1, count: ClipboardCollectionBuffer.maximumImageBytes + 1)
        XCTAssertFalse(buffer.append(.image(data: rejected, typeIdentifier: imageType, changeCount: 9)))

        let item = try XCTUnwrap(buffer.items.first)
        let pasteboardItems = item.pasteboardItems()
        XCTAssertEqual(pasteboardItems.count, 1)
        XCTAssertEqual(pasteboardItems.first?.data(forType: NSPasteboard.PasteboardType(imageType)), item.imageData)
        XCTAssertNotNil(pasteboardItems.first?.data(forType: ClipboardMonitor.processedPasteboardType))

        let fileCollectionItem = ClipboardCollectionItem(content: .files(urls: [URL(fileURLWithPath: "/tmp/collect-me.mov")]))
        let filePasteboardItems = fileCollectionItem.pasteboardItems()
        XCTAssertEqual(filePasteboardItems.first?.string(forType: .fileURL), URL(fileURLWithPath: "/tmp/collect-me.mov").absoluteString)
        XCTAssertNotNil(filePasteboardItems.first?.data(forType: ClipboardMonitor.processedPasteboardType))

        var previewBuffer = ClipboardCollectionBuffer()
        let previewPNG = try makeNoisePNG(width: 640, height: 480)
        XCTAssertTrue(previewBuffer.append(.image(data: previewPNG, typeIdentifier: imageType, changeCount: 10)))
        let thumbnailData = try XCTUnwrap(previewBuffer.items.first?.thumbnailData)
        let thumbnail = try XCTUnwrap(NSImage(data: thumbnailData))
        XCTAssertLessThanOrEqual(thumbnail.size.width, 128)
        XCTAssertLessThanOrEqual(thumbnail.size.height, 128)
    }

    func testQueueProfileChoiceSupportsCurrentBuiltInAndSavedProfiles() throws {
        let savedProfile = SavedCompressionProfile(
            name: "单项归档",
            imageResizePreset: .max4096,
            imageQuality: 0.94,
            imageFileOutputFormat: .jpeg,
            stripImageMetadata: false,
            videoOutputPreset: .high1080p,
            videoCodecPreference: .automatic,
            videoBitrateTarget: .highQuality,
            videoFrameRate: .original,
            videoIncludesAudio: true
        )
        let currentChoice = try XCTUnwrap(QueueProfileChoice.resolve(
            CompressionProfileReference.currentIdentifier,
            savedProfiles: [savedProfile]
        ))
        XCTAssertNil(currentChoice.profile)
        XCTAssertEqual(currentChoice.title, "当前设置")

        let builtInChoice = try XCTUnwrap(QueueProfileChoice.resolve(
            CompressionProfileReference.identifier(for: .emailAttachment),
            savedProfiles: []
        ))
        XCTAssertEqual(builtInChoice.profile?.imageMaximumSizeMB, 10)

        let savedIdentifier = CompressionProfileReference.identifier(for: savedProfile)
        let savedChoice = try XCTUnwrap(QueueProfileChoice.resolve(savedIdentifier, savedProfiles: [savedProfile]))
        XCTAssertEqual(savedChoice.profile, savedProfile)
        XCTAssertNil(QueueProfileChoice.resolve(savedIdentifier, savedProfiles: []), "Queued jobs should reject deleted profiles when selecting a new profile.")

        var job = CompressionQueueJob(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/photo.png"),
            securityScopeURL: URL(fileURLWithPath: "/tmp/photo.png"),
            state: .queued
        )
        XCTAssertEqual(job.profileIdentifier, CompressionProfileReference.currentIdentifier)
        job.profileIdentifier = savedChoice.identifier
        job.profileOverride = savedChoice.profile
        XCTAssertEqual(job.profileOverride?.name, "单项归档", "The selected profile snapshot remains attached to its queued item.")
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
        legacyDictionary.removeValue(forKey: "imageMaximumSizeMB")
        legacyDictionary.removeValue(forKey: "retinaDownscaleEnabled")
        legacyDictionary.removeValue(forKey: "gifConversionEnabled")
        let legacyData = try PropertyListSerialization.data(fromPropertyList: legacyDictionary, format: .binary, options: 0)

        let decoded = try PropertyListDecoder().decode(SavedCompressionProfile.self, from: legacyData)
        XCTAssertEqual(decoded.name, "旧配置")
        XCTAssertNil(decoded.videoMaximumSizeMB)
        XCTAssertNil(decoded.imageMaximumSizeMB)
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
        XCTAssertEqual(settings.imageMaximumSizeMB, 10)
        XCTAssertTrue(settings.stripImageMetadata)
        XCTAssertEqual(settings.videoOutputPreset, .compact10MB)
        XCTAssertEqual(settings.videoCodecPreference, .h264)
        XCTAssertNil(settings.videoMaximumSizeMB, "Applying a built-in preset must clear the prior custom cap.")

        settings.applyScenario(.messaging)
        XCTAssertEqual(settings.imageMaximumSizeMB, 5)

        settings.applyScenario(.webPublishing)
        XCTAssertEqual(settings.imageFileOutputFormat, .webP)
        XCTAssertTrue(settings.stripImageMetadata)
        XCTAssertEqual(settings.imageResizePreset, .max2560)
        XCTAssertEqual(CompressionScenario.webPublishing.requiredProFeature, .fileWebPOutput)
        XCTAssertNil(CompressionScenario.emailAttachment.requiredProFeature)

        settings.applyScenario(.archive)
        XCTAssertNil(settings.imageMaximumSizeMB)
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

    private func makeNoisePNG(width: Int, height: Int) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        var state: UInt32 = 0x1234_5678
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bitmap.bytesPerRow + x * 4
                for channel in 0..<3 {
                    state = state &* 1_664_525 &+ 1_013_904_223
                    pixels[offset + channel] = UInt8(truncatingIfNeeded: state >> 24)
                }
                pixels[offset + 3] = 255
            }
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
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

    private func makeTestAudio(at url: URL, durationSeconds: Double) throws {
        let sampleRate = 44_100.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000
        ]
        let audioFile = try AVAudioFile(forWriting: url, settings: settings)
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else {
            throw VideoFixtureError.cannotCreateAudioBuffer
        }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            samples[frame] = Float(sin(Double(frame) * 2 * .pi * 440 / sampleRate)) * 0.2
        }
        try audioFile.write(from: buffer)
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

    func testVideoTrimRangeValidatesBoundsAndMinimumDuration() throws {
        let valid = try VideoTrimRange(startSeconds: 0.5, endSeconds: 2.5, assetDurationSeconds: 4)
        XCTAssertEqual(valid.durationSeconds, 2, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(valid.timeRange.start), 0.5, accuracy: 0.0001)
        XCTAssertEqual(CMTimeGetSeconds(valid.timeRange.duration), 2, accuracy: 0.0001)
        XCTAssertThrowsError(try VideoTrimRange(startSeconds: -0.1, endSeconds: 1, assetDurationSeconds: 4))
        XCTAssertThrowsError(try VideoTrimRange(startSeconds: 1, endSeconds: 1.2, assetDurationSeconds: 4))
        XCTAssertThrowsError(try VideoTrimRange(startSeconds: 0, endSeconds: 5, assetDurationSeconds: 4))
        XCTAssertThrowsError(try VideoTrimRange(startSeconds: .nan, endSeconds: 1, assetDurationSeconds: 4))
        XCTAssertThrowsError(try valid.validate(against: 2))
    }

    func testQuickEditTranscodesOnlySelectedVideoRangeAndPreservesSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-video-trim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("trim-input.mp4")
        try makeTestVideo(at: inputURL, width: 640, height: 360, frameCount: 120)
        let originalBytes = try Self.fileSize(at: inputURL)
        let range = try VideoTrimRange(startSeconds: 1, endSeconds: 2.5, assetDurationSeconds: 4)
        let outputURL = try await VideoTranscoder.transcodeToSmallerMP4(
            inputURL,
            preset: .standard720p,
            codec: .h264,
            bitrateTarget: .automatic,
            maximumFrameRate: .fps30,
            includesAudio: true,
            trimRange: range,
            requiresSmallerOutput: false,
            outputDirectory: directory
        )

        XCTAssertEqual(outputURL.lastPathComponent, "trim-input-edited.mp4")
        XCTAssertEqual(try Self.fileSize(at: inputURL), originalBytes)
        XCTAssertGreaterThan(try Self.fileSize(at: outputURL), 0)
        let outputAsset = AVURLAsset(url: outputURL)
        let outputDuration = try await outputAsset.load(.duration).seconds
        XCTAssertEqual(outputDuration, 1.5, accuracy: 0.12)
        let outputVideoTracks = try await outputAsset.loadTracks(withMediaType: .video)
        XCTAssertEqual(outputVideoTracks.count, 1)
    }

    func testQuickEditExportsConfigurableTrimmedGIF() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-video-gif-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("gif-input.mp4")
        try makeTestVideo(at: inputURL, width: 320, height: 180, frameCount: 90)
        let originalBytes = try Self.fileSize(at: inputURL)
        let range = try VideoTrimRange(startSeconds: 0.5, endSeconds: 1.5, assetDurationSeconds: 3)
        let outputURL = try await GIFGenerator.generateGIF(
            from: inputURL,
            trimRange: range,
            framesPerSecond: 12,
            maximumDimension: 256,
            outputDirectory: directory
        )

        XCTAssertEqual(outputURL.lastPathComponent, "gif-input-edited.gif")
        XCTAssertEqual(try Self.fileSize(at: inputURL), originalBytes)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(imageSource), 12)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertLessThanOrEqual(max(width, height), 256)
        XCTAssertGreaterThan(min(width, height), 0)
    }

    func testQuickEditExtractsTrimmedM4AAndPreservesSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-video-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("audio-input.m4a")
        try makeTestAudio(at: inputURL, durationSeconds: 4)
        let originalBytes = try Self.fileSize(at: inputURL)
        let range = try VideoTrimRange(startSeconds: 0.5, endSeconds: 2, assetDurationSeconds: 4)
        let outputURL = try await AudioExtractor.extractM4A(from: inputURL, trimRange: range, outputDirectory: directory)

        XCTAssertEqual(outputURL.lastPathComponent, "audio-input-audio.m4a")
        XCTAssertEqual(try Self.fileSize(at: inputURL), originalBytes)
        XCTAssertGreaterThan(try Self.fileSize(at: outputURL), 0)
        let outputAsset = AVURLAsset(url: outputURL)
        let outputAudioTracks = try await outputAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(outputAudioTracks.count, 1)
        let outputDuration = try await outputAsset.load(.duration).seconds
        XCTAssertEqual(outputDuration, 1.5, accuracy: 0.2)
    }

    func testAudioExtractionReportsMissingAudioTrack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropSqueeze-video-no-audio-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputURL = directory.appendingPathComponent("silent.mp4")
        try makeTestVideo(at: inputURL, width: 320, height: 180, frameCount: 30)
        do {
            _ = try await AudioExtractor.extractM4A(from: inputURL, outputDirectory: directory)
            XCTFail("Audio extraction should reject a video without audio tracks.")
        } catch {
            XCTAssertEqual((error as? AudioExtractionError)?.errorDescription, "此视频没有可提取的音轨")
        }
    }

    func testQuickEditExportersHonorCancellationBeforeStarting() async throws {
        let cancellation = VideoTranscoderCancellation()
        cancellation.cancel()
        let missingURL = URL(fileURLWithPath: "/tmp/dropsqueeze-cancelled-media-does-not-exist.mp4")

        do {
            _ = try await GIFGenerator.generateGIF(from: missingURL, cancellation: cancellation)
            XCTFail("GIF generation should stop before reading a cancelled source.")
        } catch {
            XCTAssertEqual((error as? GIFGenerationError)?.errorDescription, "GIF 导出已取消")
        }

        do {
            _ = try await AudioExtractor.extractM4A(from: missingURL, cancellation: cancellation)
            XCTFail("Audio extraction should stop before reading a cancelled source.")
        } catch {
            XCTAssertEqual((error as? AudioExtractionError)?.errorDescription, "音频导出已取消")
        }
    }

    func testSVGMinifierCleansMetadataAndExcessivePrecision() throws {
        let rawSVG = """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <!-- Generator: Adobe Illustrator 28.0, SVG Export Plug-In . SVG Version: 6.00 Build 0)  -->
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" viewBox="0 0 100 100">
            <metadata>
                <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
                    <cc:Work rdf:about="" />
                </rdf:RDF>
            </metadata>
            <path data-name="Layer_1" d="M 10.123456 20.987654 L 30.555555 40.777777 Z" />
        </svg>
        """
        guard let data = rawSVG.data(using: .utf8) else {
            XCTFail("Failed to convert raw SVG to Data")
            return
        }

        let compressed = try XCTUnwrap(SVGCompressor.compress(data: data))
        XCTAssertLessThan(compressed.data.count, data.count)
        guard let minified = String(data: compressed.data, encoding: .utf8) else {
            XCTFail("Failed to decode minified SVG")
            return
        }
        XCTAssertFalse(minified.contains("<?xml"))
        XCTAssertFalse(minified.contains("<!DOCTYPE"))
        XCTAssertFalse(minified.contains("Adobe Illustrator"))
        XCTAssertFalse(minified.contains("<metadata>"))
        XCTAssertFalse(minified.contains("inkscape"))
        XCTAssertFalse(minified.contains("data-name"))
        XCTAssertFalse(minified.contains("10.123456"))
        XCTAssertTrue(minified.contains("10.12"))
        XCTAssertTrue(minified.contains("<path d="))

        let testURL = URL(fileURLWithPath: "/tmp/sample.svg")
        XCTAssertTrue(SVGCompressor.isSVG(url: testURL))
        XCTAssertFalse(SVGCompressor.isSVG(url: URL(fileURLWithPath: "/tmp/sample.png")))
    }

    @MainActor
    func testSavingsCardGraphicRendersSuccessfully() {
        let suiteName = "DropSqueezeTests.card.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel()
        let graphic = SavingsCardGraphic(model: model).frame(width: 380, height: 260)
        let renderer = ImageRenderer(content: graphic)
        renderer.scale = 2.0
        XCTAssertNotNil(renderer.nsImage, "SavingsCardGraphic must render to an NSImage")
    }

    @MainActor
    func testAppModelRecognizedTextCopying() {
        let model = AppModel()
        XCTAssertNil(model.latestRecognizedText)

        // Set recognized text
        let testString = "DROP SQUEEZE TEST OCR"
        model.latestRecognizedText = testString
        XCTAssertEqual(model.latestRecognizedText, testString)

        model.copyLatestRecognizedText()
        let copied = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(copied, testString)
    }

    func testVisionTextExtractorCanRecognizeText() async throws {
        let size = NSSize(width: 300, height: 100)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 28),
                .foregroundColor: NSColor.black
            ]
            let string = NSAttributedString(string: "HELLO OCR 2026", attributes: attrs)
            string.draw(at: NSPoint(x: 20, y: 35))
            return true
        }

        let recognized = await VisionTextExtractor.shared.extractText(from: image)
        XCTAssertNotNil(recognized)
        let text = recognized ?? ""
        XCTAssertTrue(text.contains("HELLO") || text.contains("OCR") || text.contains("2026"), "Vision text recognition should detect the rendered text, got: \(text)")
    }

    private enum VideoFixtureError: Error {
        case cannotCreateInput
        case cannotStartWriting
        case cannotCreatePixelBuffer
        case cannotAppendFrame
        case cannotFinishWriting
        case cannotCreateAudioBuffer
    }
}
