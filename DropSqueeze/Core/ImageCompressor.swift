import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CompressedImage {
    let data: Data
    let typeIdentifier: String
    let fileExtension: String
    let originalByteCount: Int
    var savedByteCount: Int { max(0, originalByteCount - data.count) }
}

enum ImageCompressionError: LocalizedError {
    case unsupportedFormat
    case unreadableImage
    case animatedImage
    case encodingFailed
    case webPUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "暂不支持这种图片格式"
        case .unreadableImage: return "无法读取图片"
        case .animatedImage: return "暂不处理动图，以保留全部帧"
        case .encodingFailed: return "图片编码失败"
        case .webPUnavailable: return "此 macOS 版本暂不支持 WebP 编码"
        }
    }
}

enum ImageCompressor {
    private static let supportedTypes: Set<String> = [
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.heic.identifier,
        UTType.tiff.identifier,
        UTType.webP.identifier
    ]

    static var webPEncodingAvailable: Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(UTType.webP.identifier) == true
    }

    static func compress(
        data: Data,
        typeIdentifier: String,
        options: ImageCompressionOptions = .standard
    ) throws -> CompressedImage? {
        guard supportedTypes.contains(typeIdentifier) else { throw ImageCompressionError.unsupportedFormat }
        guard !options.outputWebP || webPEncodingAvailable else { throw ImageCompressionError.webPUnavailable }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageCompressionError.unreadableImage
        }
        guard CGImageSourceGetCount(source) == 1 else { throw ImageCompressionError.animatedImage }

        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let targetType = options.outputWebP ? UTType.webP.identifier : typeIdentifier
        let resizedImage = options.resizeRetinaTo1x ? retinaOneXThumbnail(source: source, properties: sourceProperties) : nil

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            targetType as CFString,
            1,
            nil
        ) else {
            throw ImageCompressionError.encodingFailed
        }

        var destinationOptions: [CFString: Any] = [:]
        if targetType == UTType.jpeg.identifier || targetType == UTType.heic.identifier || targetType == UTType.webP.identifier {
            destinationOptions[kCGImageDestinationLossyCompressionQuality] = options.jpegQuality
        }

        if let resizedImage {
            var properties = sourceProperties
            for (key, value) in destinationOptions { properties[key] = value }
            properties[kCGImagePropertyOrientation] = 1
            properties[kCGImagePropertyDPIWidth] = 72
            properties[kCGImagePropertyDPIHeight] = 72
            CGImageDestinationAddImage(destination, resizedImage, properties as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(destination, source, 0, destinationOptions as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ImageCompressionError.encodingFailed }

        let result = Data(referencing: output)
        guard result.count < data.count else { return nil }
        guard let outputType = UTType(targetType), let fileExtension = outputType.preferredFilenameExtension else {
            throw ImageCompressionError.encodingFailed
        }
        return CompressedImage(
            data: result,
            typeIdentifier: targetType,
            fileExtension: fileExtension,
            originalByteCount: data.count
        )
    }

    private static func retinaOneXThumbnail(source: CGImageSource, properties: [CFString: Any]) -> CGImage? {
        guard let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        let dpiWidth = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let dpiHeight = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
        let dpi = max(dpiWidth, dpiHeight)
        guard dpi >= 120 else { return nil }
        let scale = max(0.5, min(1.0, 72.0 / dpi))
        let maxDimension = max(pixelWidth.intValue, pixelHeight.intValue)
        let targetDimension = max(1, Int(Double(maxDimension) * scale))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetDimension
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    static func typeIdentifier(forFileExtension fileExtension: String) -> String? {
        guard let type = UTType(filenameExtension: fileExtension.lowercased()),
              supportedTypes.contains(type.identifier) else { return nil }
        return type.identifier
    }

    static func writeCompressedFile(_ compressed: CompressedImage, beside inputURL: URL) throws -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let ext = compressed.fileExtension
        let temporaryURL = directory.appendingPathComponent(".dropsqueeze-\(UUID().uuidString).tmp")
        try compressed.data.write(to: temporaryURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        var suffix = 1
        while true {
            let outputName = suffix == 1 ? "\(stem)-compressed.\(ext)" : "\(stem)-compressed-\(suffix).\(ext)"
            let candidate = directory.appendingPathComponent(outputName)
            do {
                try FileManager.default.moveItem(at: temporaryURL, to: candidate)
                return candidate
            } catch {
                guard FileManager.default.fileExists(atPath: candidate.path) else { throw error }
                suffix += 1
            }
        }
    }

    static func compressFile(at inputURL: URL, options: ImageCompressionOptions = .standard) throws -> CompressedImage? {
        guard let typeIdentifier = typeIdentifier(forFileExtension: inputURL.pathExtension) else {
            throw ImageCompressionError.unsupportedFormat
        }
        let input = try Data(contentsOf: inputURL, options: [.mappedIfSafe])
        return try compress(data: input, typeIdentifier: typeIdentifier, options: options)
    }
}
