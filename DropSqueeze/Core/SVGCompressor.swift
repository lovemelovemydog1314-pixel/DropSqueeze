import Foundation
import UniformTypeIdentifiers

struct CompressedSVG: Sendable {
    let data: Data
    let originalByteCount: Int
    var savedByteCount: Int { max(0, originalByteCount - data.count) }
}

enum SVGCompressionError: LocalizedError {
    case unreadableSVG
    case cannotEncode

    var errorDescription: String? {
        switch self {
        case .unreadableSVG: return "无法读取 SVG 矢量文件"
        case .cannotEncode: return "SVG 编码失败"
        }
    }
}

enum SVGCompressor {
    static func isSVG(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "svg" { return true }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .svg) { return true }
        return false
    }

    static func compress(data: Data) throws -> CompressedSVG? {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SVGCompressionError.unreadableSVG
        }
        let minified = minify(svgText: text)
        guard let outputData = minified.data(using: .utf8) else {
            throw SVGCompressionError.cannotEncode
        }
        guard outputData.count < data.count else { return nil }
        return CompressedSVG(data: outputData, originalByteCount: data.count)
    }

    static func compressFile(at inputURL: URL) throws -> CompressedSVG? {
        let data = try Data(contentsOf: inputURL)
        return try compress(data: data)
    }

    static func minify(svgText: String) -> String {
        var result = svgText
        // Remove XML Declaration: <?xml ... ?>
        result = result.replacingOccurrences(of: #"<\?xml[^>]*\?>"#, with: "", options: .regularExpression)
        // Remove DOCTYPE: <!DOCTYPE ... >
        result = result.replacingOccurrences(of: #"<!DOCTYPE[^>]*>"#, with: "", options: .regularExpression)
        // Remove XML comments: <!-- ... -->
        result = result.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
        // Remove metadata blocks: <metadata>...</metadata>
        result = result.replacingOccurrences(of: #"<metadata[\s\S]*?<\/metadata>"#, with: "", options: .regularExpression)
        // Remove editor namespaces and tags (e.g. inkscape, sodipodi, sketch, adobe illustrator)
        result = result.replacingOccurrences(
            of: #"\s+(?:xmlns:(?:inkscape|sodipodi|sketch|i|adobe|x|illustrator)|(?:inkscape|sodipodi|sketch|i):[a-zA-Z0-9_\-]+)="[^"]*""#,
            with: "",
            options: .regularExpression
        )
        // Strip data-name attributes
        result = result.replacingOccurrences(of: #"\s+data-name="[^"]*""#, with: "", options: .regularExpression)
        // Collapse multiple whitespace
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Remove whitespace between tags
        result = result.replacingOccurrences(of: #">\s+<"#, with: "><", options: .regularExpression)
        // Remove whitespace before/after equals in attributes
        result = result.replacingOccurrences(of: #"\s*=\s*"#, with: "=", options: .regularExpression)
        // Remove whitespace before self-closing />
        result = result.replacingOccurrences(of: #"\s*\/>"#, with: "/>", options: .regularExpression)
        // Shorten excessive decimal precision in numbers (e.g., 12.345678 -> 12.35)
        result = result.replacingOccurrences(of: #"(\d+\.\d{2})\d+"#, with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func writeCompressedSVG(
        _ compressed: CompressedSVG,
        beside inputURL: URL,
        in outputDirectory: URL? = nil
    ) throws -> URL {
        let directory = outputDirectory ?? inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let ext = "svg"
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
}
