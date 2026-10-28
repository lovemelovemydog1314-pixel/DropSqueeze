import AppKit
import SwiftUI
import XCTest
@testable import DropSqueeze

final class LocalizationScreenshotTests: XCTestCase {

    @MainActor
    func testGenerateScreenshotsForAll10Languages() throws {
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DropSqueezeScreenshots", isDirectory: true)
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        print("[SCREENSHOTS_OUTPUT_DIR] \(tempDir.path)")

        let languages: [AppLanguage] = [
            .zhHans,
            .zhHant,
            .en,
            .ja,
            .ko,
            .de,
            .fr,
            .esES,
            .it,
            .ptBR
        ]

        let suiteName = "DropSqueezeTests.i18n.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel()

        let mockItem = HistoryItem(
            name: "Demo_Screen_Recording_2026.mp4",
            kind: .videoFile,
            originalBytes: 28_400_000,
            resultBytes: 6_200_000
        )

        for lang in languages {
            LocalizationManager.shared.currentLanguage = lang

            let langDir = tempDir.appendingPathComponent(lang.rawValue)
            try? fileManager.createDirectory(at: langDir, withIntermediateDirectories: true)

            // 1. MenuBar Overview
            let overview = MenuBarView(model: model)
                .frame(width: 380, height: 580)
            renderAndSave(view: overview, size: CGSize(width: 380, height: 580), to: langDir.appendingPathComponent("01_overview.png"))

            // 2. Drop Zone Panel
            let dropZone = DropZoneView(model: model, onClose: {})
                .frame(width: 350, height: 215)
            renderAndSave(view: dropZone, size: CGSize(width: 350, height: 215), to: langDir.appendingPathComponent("02_dropzone.png"))

            // 3. Floating Pill HUD
            let pill = FloatingPillView(model: model, onClose: {})
                .frame(width: 340, height: 56)
            renderAndSave(view: pill, size: CGSize(width: 340, height: 56), to: langDir.appendingPathComponent("03_floating_pill.png"))

            // 4. Output Comparison
            let comparison = OutputComparisonView(item: mockItem)
                .frame(width: 840, height: 520)
            renderAndSave(view: comparison, size: CGSize(width: 840, height: 520), to: langDir.appendingPathComponent("04_comparison.png"))

            // 5. Savings Card Graphic
            let savingsCard = SavingsCardGraphic(model: model)
                .frame(width: 400, height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            renderAndSave(view: savingsCard, size: CGSize(width: 400, height: 260), to: langDir.appendingPathComponent("05_savings_card.png"))

            // 6. Paywall View
            let paywall = PaywallView(model: model, purchaseManager: model.purchaseManager, onClose: {})
                .frame(width: 440, height: 560)
            renderAndSave(view: paywall, size: CGSize(width: 440, height: 560), to: langDir.appendingPathComponent("06_paywall.png"))

            // 7. Settings View (Direct)
            let settings = SettingsView(model: model, settings: model.settings, purchaseManager: model.purchaseManager)
                .frame(width: 380, height: 580)
            renderAndSave(view: settings, size: CGSize(width: 380, height: 580), to: langDir.appendingPathComponent("07_settings.png"))
        }

        // Restore language to default Simplified Chinese
        LocalizationManager.shared.currentLanguage = .zhHans

        // Assert all 10 language directories exist with 7 screenshots each
        for lang in languages {
            let langDir = tempDir.appendingPathComponent(lang.rawValue)
            XCTAssertTrue(fileManager.fileExists(atPath: langDir.path), "Directory must exist for \(lang.rawValue)")
            for filename in ["01_overview.png", "02_dropzone.png", "03_floating_pill.png", "04_comparison.png", "05_savings_card.png", "06_paywall.png", "07_settings.png"] {
                let filePath = langDir.appendingPathComponent(filename).path
                XCTAssertTrue(fileManager.fileExists(atPath: filePath), "Screenshot \(filename) must exist for \(lang.rawValue)")
            }
        }
    }

    @MainActor
    private func renderAndSave<V: View>(view: V, size: CGSize, to destinationURL: URL) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let darkBg = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        window.backgroundColor = darkBg
        window.appearance = NSAppearance(named: .darkAqua)

        let wrapped = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: darkBg))
            .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: wrapped)
        hostingView.frame = NSRect(origin: .zero, size: size)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return
        }
        rep.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return
        }
        try? pngData.write(to: destinationURL)
    }
}
