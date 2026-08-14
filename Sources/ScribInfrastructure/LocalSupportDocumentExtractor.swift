import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ScribApplication
import ScribDomain

#if os(macOS)
import PDFKit
import ZIPFoundation
#endif

public enum SupportExtractionError: LocalizedError, Equatable, Sendable {
    case unsupportedFormat(String)
    case unavailableOnPlatform
    case invalidDocument
    case protectedPDF
    case generatedByScrib
    case archiveEntryTooLarge(String)
    case missingWordContent

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(value):
            "L’extraction du format .\(value) n’est pas encore prise en charge."
        case .unavailableOnPlatform:
            "Cet extracteur sera exécuté nativement sur macOS."
        case .invalidDocument:
            "Le document est endommagé ou illisible."
        case .protectedPDF:
            "Le PDF est protégé par un mot de passe."
        case .generatedByScrib:
            "Un document généré par Scrib ne peut pas être réimporté comme support enseignant."
        case let .archiveEntryTooLarge(name):
            "La partie \(name) du document est anormalement volumineuse."
        case .missingWordContent:
            "Le document Word ne contient pas de partie OOXML exploitable."
        }
    }
}

public struct LocalSupportDocumentExtractor: SupportDocumentExtracting, Sendable {
    private let maximumXMLBytes: UInt64

    public init(maximumXMLBytes: UInt64 = 20 * 1_024 * 1_024) {
        self.maximumXMLBytes = maximumXMLBytes
    }

    public func extract(
        documentID: UUID,
        fileName: String,
        kind: SupportDocumentKind,
        from url: URL
    ) throws -> SupportDocumentExtraction {
        switch kind {
        case .word:
            guard url.pathExtension.lowercased() == "docx" else {
                throw SupportExtractionError.unsupportedFormat(url.pathExtension.lowercased())
            }
            return try extractDOCX(documentID: documentID, fileName: fileName, from: url)
        case .pdf:
            return try extractPDF(documentID: documentID, fileName: fileName, from: url)
        case .presentation, .spreadsheet, .image:
            throw SupportExtractionError.unsupportedFormat(url.pathExtension.lowercased())
        }
    }

    private func extractDOCX(
        documentID: UUID,
        fileName: String,
        from url: URL
    ) throws -> SupportDocumentExtraction {
        #if os(macOS)
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw SupportExtractionError.invalidDocument
        }

        guard let documentXML = try data(for: "word/document.xml", in: archive, required: true) else {
            throw SupportExtractionError.missingWordContent
        }
        let coreXML = try data(for: "docProps/core.xml", in: archive, required: false)
        let appXML = try data(for: "docProps/app.xml", in: archive, required: false)
        let metadata = DOCXMetadataParser.parse(coreXML: coreXML, appXML: appXML)
        if metadata.creator?.caseInsensitiveCompare("Scrib") == .orderedSame
            || metadata.application?.caseInsensitiveCompare("Scrib") == .orderedSame {
            throw SupportExtractionError.generatedByScrib
        }

        let parsed = try DOCXContentParser.parse(documentXML)
        let imageCount = archive.filter {
            $0.path.hasPrefix("word/media/") && $0.type == .file
        }.count
        var warnings: [SupportExtractionWarning] = []
        if imageCount > 0 { warnings.append(.imagesRequireReview(imageCount)) }
        if parsed.elements.isEmpty && parsed.tables.isEmpty {
            warnings.append(.noExtractableText)
        }
        return SupportDocumentExtraction(
            documentID: documentID,
            sourceFileName: fileName,
            title: metadata.title ?? parsed.elements.first(where: { $0.kind == .heading })?.text,
            textElements: parsed.elements,
            tables: parsed.tables,
            imageCount: imageCount,
            warnings: warnings
        )
        #else
        throw SupportExtractionError.unavailableOnPlatform
        #endif
    }

    private func extractPDF(
        documentID: UUID,
        fileName: String,
        from url: URL
    ) throws -> SupportDocumentExtraction {
        #if os(macOS)
        guard let document = PDFDocument(url: url) else {
            throw SupportExtractionError.invalidDocument
        }
        guard !document.isLocked else { throw SupportExtractionError.protectedPDF }

        var pages: [SupportExtractedPage] = []
        var warnings: [SupportExtractionWarning] = []
        for index in 0..<document.pageCount {
            let text = normalized(document.page(at: index)?.string ?? "")
            let hasText = !text.isEmpty
            pages.append(.init(number: index + 1, text: text, hasExtractableText: hasText))
            if !hasText { warnings.append(.scannedOrEmptyPage(index + 1)) }
        }
        if pages.allSatisfy({ !$0.hasExtractableText }) {
            warnings.append(.noExtractableText)
        }
        let title = pages.lazy
            .flatMap { $0.text.components(separatedBy: .newlines) }
            .map(normalized)
            .first { !$0.isEmpty }
        return SupportDocumentExtraction(
            documentID: documentID,
            sourceFileName: fileName,
            title: title,
            pages: pages,
            warnings: warnings
        )
        #else
        throw SupportExtractionError.unavailableOnPlatform
        #endif
    }

    #if os(macOS)
    private func data(for path: String, in archive: Archive, required: Bool) throws -> Data? {
        guard let entry = archive[path] else {
            if required { throw SupportExtractionError.missingWordContent }
            return nil
        }
        guard entry.uncompressedSize <= maximumXMLBytes else {
            throw SupportExtractionError.archiveEntryTooLarge(path)
        }
        var result = Data()
        result.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry) { chunk in result.append(chunk) }
        } catch {
            throw SupportExtractionError.invalidDocument
        }
        return result
    }
    #endif

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DOCXParsedContent: Equatable {
    var elements: [SupportTextElement]
    var tables: [SupportExtractedTable]
}

enum DOCXContentParser {
    static func parse(_ data: Data) throws -> DOCXParsedContent {
        let delegate = DOCXContentParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { throw SupportExtractionError.invalidDocument }
        return .init(elements: delegate.elements, tables: delegate.tables)
    }
}

private final class DOCXContentParserDelegate: NSObject, XMLParserDelegate {
    var elements: [SupportTextElement] = []
    var tables: [SupportExtractedTable] = []

    private var order = 0
    private var paragraphText = ""
    private var paragraphStyle = ""
    private var paragraphIsList = false
    private var isCollectingText = false
    private var tableDepth = 0
    private var currentTableRows: [[String]] = []
    private var currentRow: [String] = []
    private var currentCellParagraphs: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch localName(elementName) {
        case "tbl":
            tableDepth += 1
            if tableDepth == 1 { currentTableRows = [] }
        case "tr" where tableDepth == 1:
            currentRow = []
        case "tc" where tableDepth == 1:
            currentCellParagraphs = []
        case "p":
            paragraphText = ""
            paragraphStyle = ""
            paragraphIsList = false
        case "pStyle":
            paragraphStyle = attributeValue("val", in: attributeDict) ?? ""
        case "numPr":
            paragraphIsList = true
        case "t":
            isCollectingText = true
        case "tab":
            paragraphText.append("\t")
        case "br", "cr":
            paragraphText.append("\n")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollectingText { paragraphText.append(string) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch localName(elementName) {
        case "t":
            isCollectingText = false
        case "p":
            finishParagraph()
        case "tc" where tableDepth == 1:
            currentRow.append(currentCellParagraphs.joined(separator: "\n"))
        case "tr" where tableDepth == 1:
            if currentRow.contains(where: { !$0.isEmpty }) { currentTableRows.append(currentRow) }
        case "tbl":
            if tableDepth == 1, !currentTableRows.isEmpty {
                tables.append(.init(order: order, rows: currentTableRows))
                order += 1
            }
            tableDepth = max(tableDepth - 1, 0)
        default:
            break
        }
    }

    private func finishParagraph() {
        let text = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if tableDepth > 0 {
            currentCellParagraphs.append(text)
            return
        }

        let headingLevel = Self.headingLevel(for: paragraphStyle)
        let kind: SupportTextElementKind
        if headingLevel != nil {
            kind = .heading
        } else if paragraphIsList || paragraphStyle.localizedCaseInsensitiveContains("list") {
            kind = .listItem
        } else {
            kind = .paragraph
        }
        elements.append(.init(kind: kind, text: text, level: headingLevel, order: order))
        order += 1
    }

    private static func headingLevel(for style: String) -> Int? {
        let normalized = style.lowercased()
        if normalized == "title" { return 1 }
        for level in 1...9 where normalized == "heading\(level)" || normalized == "titre\(level)" {
            return level
        }
        return nil
    }

    private func localName(_ value: String) -> String {
        value.split(separator: ":").last.map(String.init) ?? value
    }

    private func attributeValue(_ name: String, in values: [String: String]) -> String? {
        values.first { localName($0.key) == name }?.value
    }
}

private struct DOCXMetadata {
    var title: String?
    var creator: String?
    var application: String?
}

private enum DOCXMetadataParser {
    static func parse(coreXML: Data?, appXML: Data?) -> DOCXMetadata {
        var metadata = DOCXMetadata()
        if let coreXML {
            let delegate = XMLValueParserDelegate(targets: ["title", "creator"])
            let parser = XMLParser(data: coreXML)
            parser.delegate = delegate
            if parser.parse() {
                metadata.title = delegate.values["title"]
                metadata.creator = delegate.values["creator"]
            }
        }
        if let appXML {
            let delegate = XMLValueParserDelegate(targets: ["Application"])
            let parser = XMLParser(data: appXML)
            parser.delegate = delegate
            if parser.parse() { metadata.application = delegate.values["Application"] }
        }
        return metadata
    }
}

private final class XMLValueParserDelegate: NSObject, XMLParserDelegate {
    let targets: Set<String>
    var values: [String: String] = [:]
    private var activeTarget: String?
    private var buffer = ""

    init(targets: Set<String>) { self.targets = targets }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if targets.contains(local) {
            activeTarget = local
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if activeTarget != nil { buffer.append(string) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard activeTarget == local else { return }
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { values[local] = value }
        activeTarget = nil
    }
}
