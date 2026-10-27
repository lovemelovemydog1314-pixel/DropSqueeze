import AppKit
import Foundation
import ImageIO
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

enum ClipboardCollectionContent: Equatable {
    case image(data: Data, typeIdentifier: String)
    case files(urls: [URL])
}

struct ClipboardCollectionItem: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let content: ClipboardCollectionContent
    let thumbnailData: Data?

    init(id: UUID = UUID(), createdAt: Date = Date(), content: ClipboardCollectionContent) {
        self.id = id
        self.createdAt = createdAt
        self.content = content
        self.thumbnailData = Self.makeThumbnailData(for: content)
    }

    var displayName: String {
        switch content {
        case .image(_, let typeIdentifier):
            let format = UTType(typeIdentifier)?.preferredFilenameExtension?.uppercased()
            return format.map { "剪贴板图片 · \($0)" } ?? "剪贴板图片"
        case .files(let urls):
            guard let first = urls.first else { return "空文件列表" }
            return urls.count == 1 ? first.lastPathComponent : "\(first.lastPathComponent) 等 \(urls.count) 个文件"
        }
    }

    var detail: String {
        switch content {
        case .image(let data, _): return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        case .files(let urls): return "\(urls.count) 个文件"
        }
    }

    var imageData: Data? {
        guard case .image(let data, _) = content else { return nil }
        return data
    }

    private static func makeThumbnailData(for content: ClipboardCollectionContent) -> Data? {
        guard case .image(let data, _) = content,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let sourceType = CGImageSourceGetType(source) as String?,
              UTType(sourceType)?.conforms(to: .image) == true,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
              ] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:])
    }

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }

    func pasteboardItems() -> [NSPasteboardItem] {
        switch content {
        case .image(let data, let typeIdentifier):
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
            item.setData(Data([1]), forType: ClipboardMonitor.processedPasteboardType)
            return [item]
        case .files(let urls):
            return urls.map { url in
                let item = NSPasteboardItem()
                item.setString(url.absoluteString, forType: .fileURL)
                item.setData(Data([1]), forType: ClipboardMonitor.processedPasteboardType)
                return item
            }
        }
    }
}

struct ClipboardCollectionBuffer {
    static let maximumItemCount = 12
    static let maximumImageBytes = 10 * 1_024 * 1_024
    static let maximumTotalImageBytes = 40 * 1_024 * 1_024

    private(set) var items: [ClipboardCollectionItem] = []

    @discardableResult
    mutating func append(_ payload: ClipboardPayload, createdAt: Date = Date()) -> Bool {
        let content: ClipboardCollectionContent
        switch payload {
        case .image(let data, let typeIdentifier, _):
            guard !data.isEmpty, data.count <= Self.maximumImageBytes else { return false }
            content = .image(data: data, typeIdentifier: typeIdentifier)
        case .files(let urls, _):
            let uniqueURLs = Self.uniqueFileURLs(urls)
            guard !uniqueURLs.isEmpty else { return false }
            content = .files(urls: uniqueURLs)
        }

        guard !items.contains(where: { $0.content == content }) else { return false }
        let item = ClipboardCollectionItem(createdAt: createdAt, content: content)
        var updated = [item] + items
        while updated.count > Self.maximumItemCount || Self.totalImageBytes(in: updated) > Self.maximumTotalImageBytes {
            updated.removeLast()
        }
        guard updated.contains(where: { $0.id == item.id }) else { return false }
        items = updated
        return true
    }

    mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    mutating func clear() {
        items.removeAll()
    }

    private static func totalImageBytes(in items: [ClipboardCollectionItem]) -> Int {
        items.reduce(into: 0) { total, item in
            if let data = item.imageData { total += data.count }
        }
    }

    private static func uniqueFileURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            url.isFileURL && seen.insert(url.standardizedFileURL.path).inserted
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

        if let payload = Self.readPayload(from: pasteboard, changeCount: changeCount) {
            onPayload?(payload)
        }
    }

    static func currentPayload() -> ClipboardPayload? {
        let pasteboard = NSPasteboard.general
        guard pasteboard.availableType(from: [processedPasteboardType]) == nil else { return nil }
        return readPayload(from: pasteboard, changeCount: pasteboard.changeCount)
    }

    private static func readPayload(from pasteboard: NSPasteboard, changeCount: Int) -> ClipboardPayload? {
        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL], !fileURLs.isEmpty {
            return .files(urls: fileURLs.map { $0 as URL }, changeCount: changeCount)
        }

        guard let items = pasteboard.pasteboardItems, items.count == 1,
              let item = items.first else { return nil }

        let candidates: [(NSPasteboard.PasteboardType, String)] = [
            (.png, UTType.png.identifier),
            (NSPasteboard.PasteboardType(UTType.jpeg.identifier), UTType.jpeg.identifier),
            (NSPasteboard.PasteboardType(UTType.heic.identifier), UTType.heic.identifier),
            (NSPasteboard.PasteboardType(UTType.webP.identifier), UTType.webP.identifier),
            (NSPasteboard.PasteboardType(UTType.gif.identifier), UTType.gif.identifier),
            (.tiff, UTType.tiff.identifier)
        ]

        for (pasteboardType, typeIdentifier) in candidates {
            if let data = item.data(forType: pasteboardType), !data.isEmpty {
                return .image(data: data, typeIdentifier: typeIdentifier, changeCount: changeCount)
            }
        }
        return nil
    }
}
