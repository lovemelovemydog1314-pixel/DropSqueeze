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
        case .animatedImage: return "暂不支持这种动图格式；为避免丢帧已跳过"
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
        UTType.webP.identifier,
        UTType.gif.identifier
    ]

    static var webPEncodingAvailable: Bool {
        encodingAvailable(for: UTType.webP.identifier)
    }

    static func encodingAvailable(for typeIdentifier: String) -> Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(typeIdentifier) == true
    }

    static func compress(
        data: Data,
        typeIdentifier: String,
        options: ImageCompressionOptions = .standard
    ) throws -> CompressedImage? {
        guard supportedTypes.contains(typeIdentifier) else { throw ImageCompressionError.unsupportedFormat }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageCompressionError.unreadableImage
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw ImageCompressionError.unreadableImage }
        if frameCount > 1 {
            guard typeIdentifier == UTType.gif.identifier else { throw ImageCompressionError.animatedImage }
            return try compressAnimatedGIF(source: source, originalData: data, options: options)
        }
        guard !options.outputWebP || webPEncodingAvailable else { throw ImageCompressionError.webPUnavailable }

        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let targetType = options.outputTypeIdentifier
            ?? (options.outputWebP ? UTType.webP.identifier : typeIdentifier)
        guard encodingAvailable(for: targetType) else {
            throw targetType == UTType.webP.identifier
                ? ImageCompressionError.webPUnavailable
                : ImageCompressionError.encodingFailed
        }
        let didRequestFormatConversion = options.outputTypeIdentifier != nil
            && options.outputTypeIdentifier != typeIdentifier
        let resizedImage = thumbnail(source: source, index: 0, properties: sourceProperties, options: options)

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
            destinationOptions[kCGImageDestinationLossyCompressionQuality] = min(0.96, max(0.4, options.jpegQuality))
        }

        if let resizedImage {
            var properties = options.stripMetadata ? safeImageProperties(from: sourceProperties) : sourceProperties
            for (key, value) in destinationOptions { properties[key] = value }
            properties[kCGImagePropertyPixelWidth] = resizedImage.width
            properties[kCGImagePropertyPixelHeight] = resizedImage.height
            properties[kCGImagePropertyOrientation] = 1
            if options.resizeRetinaTo1x {
                properties[kCGImagePropertyDPIWidth] = 72
                properties[kCGImagePropertyDPIHeight] = 72
            }
            CGImageDestinationAddImage(destination, resizedImage, properties as CFDictionary)
        } else if options.stripMetadata {
            guard let sourceWidth = sourceProperties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let sourceHeight = sourceProperties[kCGImagePropertyPixelHeight] as? NSNumber else {
                throw ImageCompressionError.unreadableImage
            }
            let transformOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(sourceWidth.intValue, sourceHeight.intValue)
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, transformOptions as CFDictionary) else {
                throw ImageCompressionError.unreadableImage
            }
            var properties = safeImageProperties(from: sourceProperties)
            for (key, value) in destinationOptions { properties[key] = value }
            properties[kCGImagePropertyPixelWidth] = image.width
            properties[kCGImagePropertyPixelHeight] = image.height
            properties[kCGImagePropertyOrientation] = 1
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(destination, source, 0, destinationOptions as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ImageCompressionError.encodingFailed }

        let result = Data(referencing: output)
        guard result.count < data.count || didRequestFormatConversion else { return nil }
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

    private static func thumbnail(
        source: CGImageSource,
        index: Int,
        properties: [CFString: Any],
        options: ImageCompressionOptions
    ) -> CGImage? {
        guard let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        let sourceMaxDimension = max(pixelWidth.intValue, pixelHeight.intValue)
        guard sourceMaxDimension > 0 else { return nil }
        var targetDimension = min(sourceMaxDimension, options.maxPixelDimension ?? sourceMaxDimension)
        if options.resizeRetinaTo1x {
            let dpiWidth = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
            let dpiHeight = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
            let dpi = max(dpiWidth, dpiHeight)
            if dpi >= 120 {
                let scale = max(0.5, min(1.0, 72.0 / dpi))
                targetDimension = min(targetDimension, max(1, Int(Double(sourceMaxDimension) * scale)))
            }
        }
        guard targetDimension < sourceMaxDimension else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetDimension
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary)
    }

    private static func safeImageProperties(from source: [CFString: Any]) -> [CFString: Any] {
        var safe: [CFString: Any] = [:]
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight, kCGImagePropertyOrientation] {
            if let value = source[key] { safe[key] = value }
        }
        return safe
    }

    private static func compressAnimatedGIF(
        source: CGImageSource,
        originalData: Data,
        options: ImageCompressionOptions
    ) throws -> CompressedImage? {
        let frameCount = CGImageSourceGetCount(source)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else { throw ImageCompressionError.encodingFailed }

        let sourceProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
        let sourceGIFProperties = sourceProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
        var animationProperties: [CFString: Any] = options.stripMetadata ? [:] : sourceGIFProperties
        if let loopCount = sourceGIFProperties[kCGImagePropertyGIFLoopCount] {
            animationProperties[kCGImagePropertyGIFLoopCount] = loopCount
        }
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: animationProperties] as CFDictionary
        )

        for index in 0..<frameCount {
            let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let sourceFrameGIFProperties = frameProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any] ?? [:]
            var outputProperties = options.stripMetadata ? safeImageProperties(from: frameProperties) : frameProperties
            outputProperties[kCGImagePropertyGIFDictionary] = sourceFrameGIFProperties

            if let resizedImage = thumbnail(source: source, index: index, properties: frameProperties, options: options) {
                outputProperties[kCGImagePropertyPixelWidth] = resizedImage.width
                outputProperties[kCGImagePropertyPixelHeight] = resizedImage.height
                outputProperties[kCGImagePropertyOrientation] = 1
                CGImageDestinationAddImage(destination, resizedImage, outputProperties as CFDictionary)
            } else if options.stripMetadata {
                guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                    throw ImageCompressionError.unreadableImage
                }
                CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
            } else {
                CGImageDestinationAddImageFromSource(destination, source, index, outputProperties as CFDictionary)
            }
        }

        guard CGImageDestinationFinalize(destination) else { throw ImageCompressionError.encodingFailed }
        let result = Data(referencing: output)
        guard result.count < originalData.count else { return nil }
        return CompressedImage(
            data: result,
            typeIdentifier: UTType.gif.identifier,
            fileExtension: "gif",
            originalByteCount: originalData.count
        )
    }

    static func typeIdentifier(forFileExtension fileExtension: String) -> String? {
        guard let type = UTType(filenameExtension: fileExtension.lowercased()),
              supportedTypes.contains(type.identifier) else { return nil }
        return type.identifier
    }

    static func writeCompressedFile(
        _ compressed: CompressedImage,
        beside inputURL: URL,
        in outputDirectory: URL? = nil
    ) throws -> URL {
        let directory = outputDirectory ?? inputURL.deletingLastPathComponent()
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
