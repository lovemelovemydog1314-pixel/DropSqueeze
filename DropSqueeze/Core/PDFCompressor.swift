import Foundation
import PDFKit

struct CompressedPDF {
    let outputURL: URL
    let originalByteCount: Int64
    let resultByteCount: Int64
}

enum PDFCompressionError: LocalizedError {
    case unreadable
    case encrypted
    case digitallySigned
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取 PDF，原文件已保留"
        case .encrypted: return "加密 PDF 暂不处理，原文件已保留"
        case .digitallySigned: return "已签名 PDF 不会重写，原文件已保留"
        case .writeFailed: return "PDF 优化失败，原文件已保留"
        }
    }
}

enum PDFCompressor {
    static func compressFile(at inputURL: URL, outputDirectory: URL? = nil) throws -> CompressedPDF? {
        let sourceData = try Data(contentsOf: inputURL, options: [.mappedIfSafe])
        guard sourceData.range(of: Data("/ByteRange".utf8)) == nil else {
            throw PDFCompressionError.digitallySigned
        }
        guard let document = PDFDocument(url: inputURL), document.pageCount > 0 else {
            throw PDFCompressionError.unreadable
        }
        guard !document.isEncrypted, !document.isLocked else { throw PDFCompressionError.encrypted }

        let directory = outputDirectory ?? inputURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".dropsqueeze-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let didWrite: Bool
        if #available(macOS 13.4, *) {
            let options: [PDFDocumentWriteOption: Any] = [
                .optimizeImagesForScreenOption: true,
                .saveImagesAsJPEGOption: true
            ]
            didWrite = document.write(to: temporaryURL, withOptions: options)
        } else {
            didWrite = document.write(to: temporaryURL)
        }
        guard didWrite else {
            throw PDFCompressionError.writeFailed
        }

        let fileManager = FileManager.default
        guard let sourceSize = try fileManager.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber,
              let resultSize = try fileManager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber else {
            throw PDFCompressionError.writeFailed
        }
        guard resultSize.int64Value < sourceSize.int64Value else { return nil }

        let stem = inputURL.deletingPathExtension().lastPathComponent
        var suffix = 1
        while true {
            let name = suffix == 1 ? "\(stem)-compressed.pdf" : "\(stem)-compressed-\(suffix).pdf"
            let outputURL = directory.appendingPathComponent(name)
            do {
                try fileManager.moveItem(at: temporaryURL, to: outputURL)
                return CompressedPDF(
                    outputURL: outputURL,
                    originalByteCount: sourceSize.int64Value,
                    resultByteCount: resultSize.int64Value
                )
            } catch {
                guard fileManager.fileExists(atPath: outputURL.path) else { throw error }
                suffix += 1
            }
        }
    }
}
