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
    case invalidTargetSize
    case targetSizeUnreachable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "暂不支持这种图片格式"
        case .unreadableImage: return "无法读取图片"
        case .animatedImage: return "暂不支持这种动图格式；为避免丢帧已跳过"
        case .encodingFailed: return "图片编码失败"
        case .webPUnavailable: return "此 macOS 版本暂不支持 WebP 编码"
        case .invalidTargetSize: return "图片体积上限需要设置为 0.1–5000 MB"
        case .targetSizeUnreachable: return "图片无法达到目标体积；已保留原件，请提高上限或选择更适合分享的格式与尺寸"
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
        let detectedType = (CGImageSourceGetType(source) as String?) ?? typeIdentifier
        guard supportedTypes.contains(detectedType) else { throw ImageCompressionError.unsupportedFormat }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw ImageCompressionError.unreadableImage }
        if let maximumOutputSizeMB = options.maximumOutputSizeMB {
            guard let maximumBytes = ImageOutputSizeLimit.bytes(for: maximumOutputSizeMB) else {
                throw ImageCompressionError.invalidTargetSize
            }
            return try compressToMaximumSize(
                data: data,
                typeIdentifier: detectedType,
                source: source,
                options: options,
                maximumBytes: maximumBytes
            )
        }
        if frameCount > 1 {
            guard detectedType == UTType.gif.identifier else { throw ImageCompressionError.animatedImage }
            return try compressAnimatedGIF(source: source, originalData: data, options: options)
        }
        guard !options.outputWebP || webPEncodingAvailable else { throw ImageCompressionError.webPUnavailable }

        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let sourceHasTransparency = containsTransparentPixels(source: source, properties: sourceProperties)
        let requestedTargetType = options.outputTypeIdentifier
            ?? (options.outputWebP ? UTType.webP.identifier : detectedType)
        // JPEG has no alpha channel. Preserve transparency by writing PNG instead of silently flattening it.
        let targetType = sourceHasTransparency && requestedTargetType == UTType.jpeg.identifier
            ? UTType.png.identifier
            : requestedTargetType
        guard encodingAvailable(for: targetType) else {
            throw targetType == UTType.webP.identifier
                ? ImageCompressionError.webPUnavailable
                : ImageCompressionError.encodingFailed
        }
        let didRequestFormatConversion = targetType != detectedType
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

    private static func compressToMaximumSize(
        data: Data,
        typeIdentifier: String,
        source: CGImageSource,
        options: ImageCompressionOptions,
        maximumBytes: Int64
    ) throws -> CompressedImage? {
        let unrestricted = options.adjusting(clearMaximumSizeLimit: true)
        if Int64(data.count) <= maximumBytes {
            return try compress(data: data, typeIdentifier: typeIdentifier, options: unrestricted)
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ImageCompressionError.unreadableImage
        }
        let sourceMaximumDimension = max(width.intValue, height.intValue)
        guard sourceMaximumDimension > 0 else { throw ImageCompressionError.unreadableImage }
        var dimension = min(sourceMaximumDimension, options.maxPixelDimension ?? sourceMaximumDimension)
        let minimumDimension = min(64, dimension)
        let requestedType = options.outputTypeIdentifier
            ?? (options.outputWebP ? UTType.webP.identifier : typeIdentifier)
        let hasTransparency = containsTransparentPixels(source: source, properties: properties)
        let resolvedType = hasTransparency && requestedType == UTType.jpeg.identifier
            ? UTType.png.identifier
            : requestedType
        let supportsQualitySearch = [UTType.jpeg.identifier, UTType.heic.identifier, UTType.webP.identifier]
            .contains(resolvedType)
        let highestQuality = min(0.96, max(0.4, options.jpegQuality))
        let lowestQuality = 0.4
        let maximumDimensionAttempts = 12
        var attempts = 0

        while attempts < maximumDimensionAttempts {
            attempts += 1
            let dimensionOptions = unrestricted.adjusting(maxPixelDimension: dimension)
            let highQualityCandidate = try compress(
                data: data,
                typeIdentifier: typeIdentifier,
                options: dimensionOptions.adjusting(jpegQuality: highestQuality)
            )
            if let highQualityCandidate, Int64(highQualityCandidate.data.count) <= maximumBytes {
                return highQualityCandidate
            }

            var smallestObservedSize = highQualityCandidate?.data.count ?? data.count
            if supportsQualitySearch, highestQuality > lowestQuality {
                let lowQualityCandidate = try compress(
                    data: data,
                    typeIdentifier: typeIdentifier,
                    options: dimensionOptions.adjusting(jpegQuality: lowestQuality)
                )
                smallestObservedSize = min(smallestObservedSize, lowQualityCandidate?.data.count ?? data.count)
                if let lowQualityCandidate, Int64(lowQualityCandidate.data.count) <= maximumBytes {
                    var bestCandidate = lowQualityCandidate
                    var lowerQuality = lowestQuality
                    var upperQuality = highestQuality
                    for _ in 0..<6 {
                        let midpoint = (lowerQuality + upperQuality) / 2
                        let candidate = try compress(
                            data: data,
                            typeIdentifier: typeIdentifier,
                            options: dimensionOptions.adjusting(jpegQuality: midpoint)
                        )
                        if let candidate, Int64(candidate.data.count) <= maximumBytes {
                            bestCandidate = candidate
                            lowerQuality = midpoint
                        } else {
                            upperQuality = midpoint
                        }
                    }
                    return bestCandidate
                }
            }

            guard dimension > minimumDimension else { break }
            let sizeRatio = sqrt(Double(maximumBytes) / Double(max(1, smallestObservedSize)))
            let scale = min(0.85, max(0.2, sizeRatio * 0.9))
            let proposedDimension = Int((Double(dimension) * scale).rounded(.down))
            dimension = max(minimumDimension, min(dimension - 1, proposedDimension))
        }

        throw ImageCompressionError.targetSizeUnreachable
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
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight, kCGImagePropertyOrientation,
                    kCGImagePropertyProfileName, kCGImagePropertyColorModel] {
            if let value = source[key] { safe[key] = value }
        }
        return safe
    }

    private static func containsTransparentPixels(source: CGImageSource, properties: [CFString: Any]) -> Bool {
        guard (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue == true else { return false }
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return true }
        // Decoding huge images just to inspect alpha can consume hundreds of megabytes.
        // Preserve alpha conservatively above this bound.
        let maximumPixels = 12_000_000
        guard width <= maximumPixels / height else { return true }
        guard let image = CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        ) else { return true }

        let bytesPerRow = width * 4
        guard let pixels = calloc(height, bytesPerRow) else { return true }
        guard let context = CGContext(
                data: pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                ).rawValue
              ) else {
            free(pixels)
            return true
        }
        defer { free(pixels) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let alphaOffset = 3
        for row in 0..<height {
            let rowStart = pixels.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width where rowStart[column * 4 + alphaOffset] < 255 {
                return true
            }
        }
        return false
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

    static func detectedTypeIdentifier(at url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) as String?,
              supportedTypes.contains(type) else { return nil }
        return type
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
        guard let typeIdentifier = detectedTypeIdentifier(at: inputURL)
                ?? typeIdentifier(forFileExtension: inputURL.pathExtension) else {
            throw ImageCompressionError.unsupportedFormat
        }
        let input = try Data(contentsOf: inputURL, options: [.mappedIfSafe])
        return try compress(data: input, typeIdentifier: typeIdentifier, options: options)
    }
}

private extension ImageCompressionOptions {
    func adjusting(
        maxPixelDimension: Int? = nil,
        jpegQuality: Double? = nil,
        clearMaximumSizeLimit: Bool = false
    ) -> ImageCompressionOptions {
        ImageCompressionOptions(
            resizeRetinaTo1x: resizeRetinaTo1x,
            outputWebP: outputWebP,
            outputTypeIdentifier: outputTypeIdentifier,
            maxPixelDimension: maxPixelDimension ?? self.maxPixelDimension,
            jpegQuality: jpegQuality ?? self.jpegQuality,
            stripMetadata: stripMetadata,
            maximumOutputSizeMB: clearMaximumSizeLimit ? nil : maximumOutputSizeMB
        )
    }
}
