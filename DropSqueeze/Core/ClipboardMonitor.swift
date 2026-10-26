import AppKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardPayload {
    case image(data: Data, typeIdentifier: String, changeCount: Int)
    case files(urls: [URL], changeCount: Int)

    var changeCount: Int {
        switch self {
        case .image(_, _, let changeCount), .files(_, let changeCount): return changeCount
        }
    }
}

final class ClipboardMonitor {
    static let processedPasteboardType = NSPasteboard.PasteboardType("com.dropsqueeze.processed")

    var onPayload: ((ClipboardPayload) -> Void)?
    var onExternalChange: (() -> Void)?

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.inspectPasteboard()
        }
        timer?.tolerance = 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func inspectPasteboard() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard pasteboard.availableType(from: [Self.processedPasteboardType]) == nil else { return }
        onExternalChange?()

        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL], !fileURLs.isEmpty {
            onPayload?(.files(urls: fileURLs.map { $0 as URL }, changeCount: changeCount))
            return
        }

        guard let items = pasteboard.pasteboardItems, items.count == 1,
              let item = items.first else { return }

        let candidates: [(NSPasteboard.PasteboardType, String)] = [
            (.png, UTType.png.identifier),
            (NSPasteboard.PasteboardType(UTType.jpeg.identifier), UTType.jpeg.identifier),
            (NSPasteboard.PasteboardType(UTType.heic.identifier), UTType.heic.identifier),
            (NSPasteboard.PasteboardType(UTType.webP.identifier), UTType.webP.identifier),
            (.tiff, UTType.tiff.identifier)
        ]

        for (pasteboardType, typeIdentifier) in candidates {
            if let data = item.data(forType: pasteboardType), !data.isEmpty {
                onPayload?(.image(data: data, typeIdentifier: typeIdentifier, changeCount: changeCount))
                return
            }
        }
    }
}
