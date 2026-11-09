import Foundation
import UniformTypeIdentifiers

struct CompressedSVG: Sendable {
    let data: Data
    let originalByteCount: Int
    var savedByteCount: Int { max(0, originalByteCount - data.count) }
}

enum SVGCompressionError: LocalizedError {
    case unreadableSVG
    case malformedSVG
    case cannotEncode
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unreadableSVG: return "无法读取 SVG 矢量文件"
        case .malformedSVG: return "SVG 结构无法解析，已保留原文件"
        case .cannotEncode: return "SVG 编码失败"
        case .verificationFailed: return "SVG 压缩校验未通过，已保留原文件"
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
        let minified = try SVGDocumentOptimizer.optimizedText(from: data)
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

/// Minifies SVG documents without ever rewriting drawing content.
///
/// The document is parsed into a tree first, so the optimizer only touches things that are
/// provably invisible: comments, DOCTYPE, `<metadata>` blocks, editor bookkeeping attributes
/// (`data-name`, Inkscape/Sodipodi/Sketch namespaces) and white space between elements.
/// Numeric attribute values only lose redundant trailing zeros (`10.5000` -> `10.5`), which is an
/// exact value. Path data, transforms, CSS, `<text>` content and prolog instructions such as
/// `xml-stylesheet` are copied verbatim.
///
/// The result is serialized and parsed back; if the re-parsed tree differs from the one that was
/// meant to be written, the optimizer refuses to produce output and the caller keeps the original.
enum SVGDocumentOptimizer {
    private static let editorNamespacePrefixes: Set<String> = ["inkscape", "sodipodi", "sketch"]

    /// Elements whose white space participates in rendering. Text inside them is preserved verbatim.
    private static let whitespaceSensitiveElements: Set<String> = [
        "text", "tspan", "textPath", "tref", "altGlyph", "style", "script", "foreignObject"
    ]

    /// Attributes whose values are numeric lists. Only redundant trailing zeros are removed there.
    private static let numericAttributes: Set<String> = [
        "d", "points", "viewBox", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry",
        "width", "height", "transform", "gradientTransform", "patternTransform", "stroke-width",
        "stroke-dasharray", "stroke-dashoffset", "stroke-miterlimit", "font-size", "letter-spacing",
        "word-spacing", "opacity", "fill-opacity", "stroke-opacity", "offset", "pathLength",
        "startOffset", "dx", "dy", "rotate", "textLength", "markerWidth", "markerHeight",
        "refX", "refY", "baseFrequency", "stdDeviation", "k1", "k2", "k3", "k4", "fr"
    ]

    private static let decimalPattern = try? NSRegularExpression(pattern: #"[-+]?[0-9]+\.[0-9]+"#)

    static func optimizedText(from data: Data) throws -> String {
        let document = try SVGTreeBuilder.build(from: data)
        optimize(document.root, preserveSpace: false)

        let serialized = SVGCompactSerializer.serialize(document)
        guard let reparsed = try? SVGTreeBuilder.build(from: Data(serialized.utf8)),
              treesMatch(document, reparsed) else {
            throw SVGCompressionError.verificationFailed
        }
        return serialized
    }

    // MARK: - Reductions

    private static func optimize(_ node: SVGNode, preserveSpace: Bool) {
        let nodeLocalName = localName(of: node.name)
        // `xml:space="preserve"` is emitted by many editors on the root element; white space only
        // matters where character data is rendered, which is exactly what the text containers track.
        let keepSpace = preserveSpace || whitespaceSensitiveElements.contains(nodeLocalName)

        node.attributes = node.attributes.compactMap { attribute in
            if attribute.name == "data-name" { return nil }
            if attribute.name.hasPrefix("xmlns:") {
                let declaredPrefix = String(attribute.name.dropFirst("xmlns:".count))
                if editorNamespacePrefixes.contains(declaredPrefix) { return nil }
            }
            if let attributePrefix = prefix(of: attribute.name),
               editorNamespacePrefixes.contains(attributePrefix) { return nil }
            guard numericAttributes.contains(attribute.name) else { return attribute }
            return (attribute.name, trimmingRedundantZeros(in: attribute.value))
        }

        var children: [SVGNodeChild] = []
        children.reserveCapacity(node.children.count)
        for child in node.children {
            switch child {
            case .element(let element):
                let childLocalName = localName(of: element.name)
                let isEditorElement = prefix(of: element.name).map { editorNamespacePrefixes.contains($0) } ?? false
                if isEditorElement || childLocalName == "metadata" { continue }
                optimize(element, preserveSpace: keepSpace)
                children.append(.element(element))
            case .text(let text):
                if !keepSpace, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                children.append(.text(text))
            default:
                children.append(child)
            }
        }
        node.children = children
    }

    private static func localName(of name: String) -> String {
        guard let separator = name.lastIndex(of: ":") else { return name }
        return String(name[name.index(after: separator)...])
    }

    private static func prefix(of name: String) -> String? {
        guard let separator = name.lastIndex(of: ":") else { return nil }
        return String(name[..<separator])
    }

    // MARK: - Number normalisation

    private static func trimmingRedundantZeros(in value: String) -> String {
        guard value.contains("."), let pattern = decimalPattern else { return value }
        let matches = pattern.matches(in: value, range: NSRange(value.startIndex..., in: value))
        guard !matches.isEmpty else { return value }

        var result = ""
        var cursor = value.startIndex
        for match in matches {
            guard let range = Range(match.range, in: value) else { continue }
            result += value[cursor..<range.lowerBound]
            result += trimmedDecimal(String(value[range]))
            cursor = range.upperBound
        }
        result += value[cursor...]
        return result
    }

    private static func trimmedDecimal(_ token: String) -> String {
        guard token.contains(".") else { return token }
        var trimmed = token
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        guard let original = Double(token),
              let candidate = Double(trimmed),
              original == candidate else { return token }
        return trimmed
    }

    // MARK: - Verification

    private static func treesMatch(_ left: SVGDocument, _ right: SVGDocument) -> Bool {
        guard processingInstructionsMatch(left.prolog, right.prolog) else { return false }
        return treesMatch(left.root, right.root)
    }

    private static func processingInstructionsMatch(
        _ left: [SVGProcessingInstruction],
        _ right: [SVGProcessingInstruction]
    ) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { $0.target == $1.target && $0.data == $1.data }
    }

    private static func treesMatch(_ left: SVGNode, _ right: SVGNode) -> Bool {
        guard left.name == right.name else { return false }
        guard attributeMap(left) == attributeMap(right) else { return false }

        let leftChildren = mergedCharacterData(of: left)
        let rightChildren = mergedCharacterData(of: right)
        guard leftChildren.count == rightChildren.count else { return false }

        for (leftChild, rightChild) in zip(leftChildren, rightChildren) {
            switch (leftChild, rightChild) {
            case let (.element(leftElement), .element(rightElement)):
                guard treesMatch(leftElement, rightElement) else { return false }
            case let (.text(leftText), .text(rightText)):
                guard leftText == rightText else { return false }
            case let (.processingInstruction(leftTarget, leftData), .processingInstruction(rightTarget, rightData)):
                guard leftTarget == rightTarget, leftData == rightData else { return false }
            default:
                return false
            }
        }
        return true
    }

    /// Consecutive character-data nodes are one text run; parsing merges what serialization splits.
    private static func mergedCharacterData(of node: SVGNode) -> [SVGNodeChild] {
        var children: [SVGNodeChild] = []
        children.reserveCapacity(node.children.count)
        for child in node.children {
            switch child {
            case .text(let text), .cdata(let text):
                if case .text(let existing)? = children.last {
                    children[children.count - 1] = .text(existing + text)
                } else {
                    children.append(.text(text))
                }
            default:
                children.append(child)
            }
        }
        return children
    }

    private static func attributeMap(_ node: SVGNode) -> [String: String] {
        Dictionary(node.attributes.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Tree

struct SVGDocument {
    var prolog: [SVGProcessingInstruction]
    var root: SVGNode
}

struct SVGProcessingInstruction {
    let target: String
    let data: String?
}

final class SVGNode {
    let name: String
    var attributes: [(name: String, value: String)]
    var children: [SVGNodeChild]

    init(name: String, attributes: [(name: String, value: String)], children: [SVGNodeChild]) {
        self.name = name
        self.attributes = attributes
        self.children = children
    }
}

enum SVGNodeChild {
    case element(SVGNode)
    case text(String)
    case cdata(String)
    case processingInstruction(target: String, data: String?)
}

// MARK: - Parser

enum SVGTreeBuilder {
    static func build(from data: Data) throws -> SVGDocument {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        let delegate = SVGTreeBuilderDelegate()
        parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil, let root = delegate.root else {
            throw SVGCompressionError.malformedSVG
        }
        return SVGDocument(prolog: delegate.prolog, root: root)
    }
}

private final class SVGTreeBuilderDelegate: NSObject, XMLParserDelegate {
    private(set) var root: SVGNode?
    private(set) var prolog: [SVGProcessingInstruction] = []
    private(set) var failure: Error?
    private var stack: [SVGNode] = []
    private var pendingText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        flushText()
        let attributes = attributeDict
            .map { (name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        let node = SVGNode(name: elementName, attributes: attributes, children: [])
        if let parent = stack.last {
            parent.children.append(.element(node))
        } else if root == nil {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        flushText()
        guard !stack.isEmpty else { return }
        stack.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        pendingText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        flushText()
        guard let text = String(data: CDATABlock, encoding: .utf8) else { return }
        stack.last?.children.append(.cdata(text))
    }

    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        flushText()
        guard target.lowercased() != "xml" else { return }
        // Instructions such as `xml-stylesheet` live outside the root element and affect rendering,
        // so they are kept verbatim instead of being dropped with the rest of the prolog.
        if stack.isEmpty {
            prolog.append(SVGProcessingInstruction(target: target, data: data))
        } else {
            stack.last?.children.append(.processingInstruction(target: target, data: data))
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil { failure = parseError }
    }

    private func flushText() {
        guard !pendingText.isEmpty else { return }
        let text = pendingText
        pendingText = ""
        stack.last?.children.append(.text(text))
    }
}

// MARK: - Serializer

enum SVGCompactSerializer {
    static func serialize(_ document: SVGDocument) -> String {
        var output = ""
        write(document.prolog, into: &output)
        write(document.root, into: &output)
        return output
    }

    private static func write(_ instructions: [SVGProcessingInstruction], into output: inout String) {
        for instruction in instructions {
            output += "<?" + instruction.target
            if let data = instruction.data, !data.isEmpty { output += " " + data }
            output += "?>"
        }
    }

    private static func write(_ node: SVGNode, into output: inout String) {
        output += "<" + node.name
        for attribute in node.attributes {
            output += " " + attribute.name + "=\"" + escapeAttribute(attribute.value) + "\""
        }
        guard !node.children.isEmpty else {
            output += "/>"
            return
        }
        output += ">"
        for child in node.children {
            switch child {
            case .element(let element):
                write(element, into: &output)
            case .text(let text):
                output += escapeText(text)
            case .cdata(let text):
                output += "<![CDATA[" + text + "]]>"
            case .processingInstruction(let target, let data):
                write([SVGProcessingInstruction(target: target, data: data)], into: &output)
            }
        }
        output += "</" + node.name + ">"
    }

    private static func escapeAttribute(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "\n": escaped += "&#10;"
            case "\r": escaped += "&#13;"
            case "\t": escaped += "&#9;"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    private static func escapeText(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case "\r": escaped += "&#13;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
