import Foundation
import ScribApplication
import ScribDomain

public struct OOXMLDocumentRenderer: StructuredDocumentRendering, Sendable {
    public enum RenderingError: Error, Equatable {
        case missingImageAsset(String)
        case invalidTable(String)
    }

    private struct SourceRelationship { var id: String; var source: CourseDocumentSource }
    private struct AudioRelationship { var id: String; var timestamp: Int }
    private struct ImageRelationship {
        var id: String
        var asset: CourseDocumentImageAsset
        var mediaName: String
        var drawingID: Int
    }

    public init() {}

    public func render(_ document: CourseDocument, to destination: URL) throws {
        let package = try buildPackage(for: document)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try package.write(to: destination, options: .atomic)
    }

    public func data(for document: CourseDocument) throws -> Data { try buildPackage(for: document) }

    private func buildPackage(for document: CourseDocument) throws -> Data {
        let sources = document.sources.enumerated().map { SourceRelationship(id: "rId\($0.offset + 6)", source: $0.element) }
        let timestamps = Set(document.sections.flatMap(\.blocks).compactMap { block -> Int? in
            guard case let .callout(_, _, _, timestamp?) = block else { return nil }
            return max(Int(timestamp.rounded()), 0)
        }).sorted()
        let audio = timestamps.enumerated().map {
            AudioRelationship(id: "rId\(sources.count + $0.offset + 6)", timestamp: $0.element)
        }
        let referencedIDs = document.sections.flatMap(\.blocks).compactMap { block -> String? in
            guard case let .figure(figure) = block else { return nil }
            return figure.assetID
        }.reduce(into: [String]()) { result, id in
            if !result.contains(id) { result.append(id) }
        }
        let assets = document.imageAssets.reduce(into: [String: CourseDocumentImageAsset]()) { result, asset in
            if result[asset.id] == nil { result[asset.id] = asset }
        }
        let images = try referencedIDs.enumerated().map { index, id -> ImageRelationship in
            guard let asset = assets[id] else { throw RenderingError.missingImageAsset(id) }
            return ImageRelationship(
                id: "rId\(sources.count + audio.count + index + 6)",
                asset: asset,
                mediaName: "image\(index + 1).\(asset.format.fileExtension)",
                drawingID: index + 1
            )
        }

        var entries = [
            entry("[Content_Types].xml", contentTypes(images)),
            entry("_rels/.rels", rootRelationships),
            entry("docProps/app.xml", appProperties),
            entry("docProps/core.xml", coreProperties(for: document)),
            entry("word/_rels/document.xml.rels", documentRelationships(sources: sources, audio: audio, images: images)),
            entry("word/document.xml", try documentXML(document, sources: sources, audio: audio, images: images)),
            entry("word/footer1.xml", footerXML),
            entry("word/header1.xml", headerXML(for: document)),
            entry("word/numbering.xml", numberingXML),
            entry("word/settings.xml", settingsXML),
            entry("word/styles.xml", stylesXML)
        ]
        entries += images.map { DeterministicZIPArchive.Entry(path: "word/media/\($0.mediaName)", data: $0.asset.data) }
        return try DeterministicZIPArchive().makeArchive(entries: entries)
    }

    private func entry(_ path: String, _ value: String) -> DeterministicZIPArchive.Entry {
        .init(path: path, data: Data(value.utf8))
    }

    private func contentTypes(_ images: [ImageRelationship]) -> String {
        let imageDefaults = Set(images.map(\.asset.format)).sorted { $0.rawValue < $1.rawValue }.map {
            "<Default Extension=\"\($0.fileExtension)\" ContentType=\"\($0.contentType)\"/>"
        }.joined()
        return xmlHeader + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>\(imageDefaults)
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
          <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
          <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
          <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """
    }

    private var rootRelationships: String { xmlHeader + """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
      <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
    </Relationships>
    """ }

    private var appProperties: String { xmlHeader + """
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Scrib</Application><AppVersion>0.1</AppVersion></Properties>
    """ }

    private func coreProperties(for document: CourseDocument) -> String {
        let date = Self.iso8601String(from: document.generatedAt)
        return xmlHeader + """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(escape(document.title))</dc:title><dc:creator>Scrib</dc:creator><cp:lastModifiedBy>Scrib</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">\(date)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(date)</dcterms:modified></cp:coreProperties>
        """
    }

    private func documentRelationships(sources: [SourceRelationship], audio: [AudioRelationship], images: [ImageRelationship]) -> String {
        let sourceLinks = sources.map { "<Relationship Id=\"\($0.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(escapeAttribute($0.source.url.absoluteString))\" TargetMode=\"External\"/>" }.joined()
        let audioLinks = audio.map { "<Relationship Id=\"\($0.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"scrib://audio?t=\($0.timestamp)\" TargetMode=\"External\"/>" }.joined()
        let imageLinks = images.map { "<Relationship Id=\"\($0.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\($0.mediaName)\"/>" }.joined()
        return xmlHeader + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/><Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>\(sourceLinks)\(audioLinks)\(imageLinks)</Relationships>
        """
    }

    private func documentXML(_ document: CourseDocument, sources: [SourceRelationship], audio: [AudioRelationship], images: [ImageRelationship]) throws -> String {
        var body = titleBlock(document) + tableOfContents(document.sections, includesSources: !sources.isEmpty)
        for (index, section) in document.sections.enumerated() {
            body += heading(section.title, bookmark: "section_\(index + 1)", bookmarkID: index + 1)
            for (blockIndex, block) in section.blocks.enumerated() {
                switch block {
                case let .paragraph(text): body += paragraph(text)
                case let .bullets(items): body += items.map(bullet).joined()
                case let .table(table): body += try tableXML(table)
                case let .figure(figure):
                    guard let relationship = images.first(where: { $0.asset.id == figure.assetID }) else { throw RenderingError.missingImageAsset(figure.assetID) }
                    body += figureXML(figure, relationship: relationship)
                case let .callout(kind, title, text, timestamp):
                    let relationshipID = timestamp.flatMap { value in audio.first(where: { $0.timestamp == max(Int(value.rounded()), 0) })?.id }
                    body += callout(kind: kind, title: title, body: text, audioTimestamp: timestamp, audioRelationshipID: relationshipID)
                }
                if blockIndex < section.blocks.count - 1 {
                    switch block {
                    case .table, .callout:
                        body += "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"80\"/></w:pPr></w:p>"
                    default:
                        break
                    }
                }
            }
        }
        if !sources.isEmpty {
            body += heading("Sources et vérifications", bookmark: "sources", bookmarkID: document.sections.count + 1)
            for relationship in sources {
                let source = relationship.source
                body += """
                <w:p><w:pPr><w:pStyle w:val="Source"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>\(escape(source.authority)) — </w:t></w:r><w:hyperlink r:id="\(relationship.id)"><w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr><w:t>\(escape(source.title))</w:t></w:r></w:hyperlink><w:r><w:t xml:space="preserve"> (vérifié le \(Self.frenchDateString(from: source.verifiedAt)))</w:t></w:r></w:p>
                """
            }
        }
        body += """
        <w:sectPr><w:headerReference w:type="default" r:id="rId1"/><w:footerReference w:type="default" r:id="rId2"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1273" w:right="1273" w:bottom="1273" w:left="1273" w:header="708" w:footer="708" w:gutter="0"/><w:cols w:space="708"/><w:docGrid w:linePitch="360"/></w:sectPr>
        """
        return xmlHeader + """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>\(body)</w:body></w:document>
        """
    }

    private func titleBlock(_ document: CourseDocument) -> String {
        var result = paragraph(document.kind == .fullCourse ? "COURS STRUCTURÉ" : "FICHE DE RÉVISION", style: "Kicker")
        result += paragraph(document.title, style: "Title") + paragraph(document.subtitle, style: "Subtitle")
        for item in document.metadata {
            result += "<w:p><w:pPr><w:pStyle w:val=\"Metadata\"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\">\(escape(item.label)) : </w:t></w:r><w:r><w:t>\(escape(item.value))</w:t></w:r></w:p>"
        }
        return result + paragraph("Document de démonstration généré localement par Scrib. Le contenu est fictif et ne constitue pas une référence médicale.", style: "Disclaimer")
    }

    private func tableOfContents(_ sections: [CourseDocumentSection], includesSources: Bool) -> String {
        var result = paragraph("Sommaire", style: "Heading1")
        for (index, section) in sections.enumerated() {
            result += internalLink(section.title, anchor: "section_\(index + 1)")
        }
        if includesSources { result += internalLink("Sources et vérifications", anchor: "sources") }
        return result
    }

    private func internalLink(_ text: String, anchor: String) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"TOC1\"/></w:pPr><w:hyperlink w:anchor=\"\(anchor)\" w:history=\"1\"><w:r><w:rPr><w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:t>\(escape(text))</w:t></w:r></w:hyperlink></w:p>"
    }

    private func heading(_ text: String, bookmark: String, bookmarkID: Int) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:bookmarkStart w:id=\"\(bookmarkID)\" w:name=\"\(bookmark)\"/><w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r><w:bookmarkEnd w:id=\"\(bookmarkID)\"/></w:p>"
    }

    private func paragraph(_ text: String, style: String = "Normal") -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r></w:p>"
    }

    private func bullet(_ text: String) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"ListBullet\"/><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r></w:p>"
    }

    private func tableXML(_ table: CourseDocumentTable) throws -> String {
        guard !table.headers.isEmpty, table.headers.count <= 6, table.rows.allSatisfy({ $0.count == table.headers.count }) else { throw RenderingError.invalidTable(table.caption ?? "table") }
        let weights = table.columnWidthWeights.count == table.headers.count && table.columnWidthWeights.allSatisfy({ $0 > 0 }) ? table.columnWidthWeights : Array(repeating: 1, count: table.headers.count)
        let total = weights.reduce(0, +)
        var widths = weights.map { 9360 * $0 / total }
        widths[widths.count - 1] += 9360 - widths.reduce(0, +)
        var result = table.caption.map { paragraph($0, style: "TableCaption") } ?? ""
        result += "<w:tbl><w:tblPr><w:tblW w:w=\"9360\" w:type=\"dxa\"/><w:tblInd w:w=\"120\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/><w:tblBorders><w:top w:val=\"single\" w:sz=\"6\" w:color=\"B8C2D1\"/><w:left w:val=\"single\" w:sz=\"6\" w:color=\"B8C2D1\"/><w:bottom w:val=\"single\" w:sz=\"6\" w:color=\"B8C2D1\"/><w:right w:val=\"single\" w:sz=\"6\" w:color=\"B8C2D1\"/><w:insideH w:val=\"single\" w:sz=\"4\" w:color=\"D8DEE8\"/><w:insideV w:val=\"single\" w:sz=\"4\" w:color=\"D8DEE8\"/></w:tblBorders><w:tblCellMar><w:top w:w=\"80\" w:type=\"dxa\"/><w:left w:w=\"120\" w:type=\"dxa\"/><w:bottom w:w=\"80\" w:type=\"dxa\"/><w:right w:w=\"120\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid>\(widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined())</w:tblGrid>"
        result += tableRow(table.headers, widths: widths, isHeader: true)
        for row in table.rows { result += tableRow(row, widths: widths, isHeader: false) }
        return result + "</w:tbl>"
    }

    private func tableRow(_ cells: [String], widths: [Int], isHeader: Bool) -> String {
        let header = isHeader ? "<w:tblHeader/>" : ""
        let content = zip(cells, widths).map { cell, width in
            let shade = isHeader ? "<w:shd w:val=\"clear\" w:fill=\"EAF0FF\"/>" : ""
            let bold = isHeader ? "<w:rPr><w:b/></w:rPr>" : ""
            return "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/><w:vAlign w:val=\"center\"/>\(shade)</w:tcPr><w:p><w:r>\(bold)<w:t xml:space=\"preserve\">\(escape(cell))</w:t></w:r></w:p></w:tc>"
        }.joined()
        return "<w:tr><w:trPr>\(header)</w:trPr>\(content)</w:tr>"
    }

    private func figureXML(_ figure: CourseDocumentFigure, relationship: ImageRelationship) -> String {
        let width = max(72, min(figure.widthPoints, 468))
        let cx = Int(width * 12_700)
        let aspect = Double(relationship.asset.heightPixels) / Double(max(relationship.asset.widthPixels, 1))
        let cy = Int(Double(cx) * aspect)
        return """
        <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(relationship.drawingID)" name="Figure \(relationship.drawingID)" descr="\(escapeAttribute(figure.altText))"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="\(escapeAttribute(relationship.mediaName))"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(relationship.id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>\(paragraph(figure.caption, style: "FigureCaption"))
        """
    }

    private func callout(kind: CourseDocumentCalloutKind, title: String, body: String, audioTimestamp: TimeInterval?, audioRelationshipID: String?) -> String {
        let colors: (String, String) = switch kind {
        case .information: ("F4F6F9", "1F3A5F")
        case .uncertainty: ("FFF8E1", "7A5A00")
        case .medicalImportance: ("FDECEC", "9B1C1C")
        case .scientificUpdate: ("EAF4EE", "276749")
        }
        let timestamp = audioTimestamp.map { " — Audio \(Self.timestamp($0))" } ?? ""
        let titleRun = "<w:r><w:rPr><w:b/><w:color w:val=\"\(colors.1)\"/></w:rPr><w:t>\(escape(title + timestamp))</w:t></w:r>"
        let linkedTitle = audioRelationshipID.map { "<w:hyperlink r:id=\"\($0)\">\(titleRun)</w:hyperlink>" } ?? titleRun
        return """
        <w:tbl><w:tblPr><w:tblW w:w="9360" w:type="dxa"/><w:tblInd w:w="120" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders><w:top w:val="single" w:sz="8" w:color="\(colors.1)"/><w:left w:val="single" w:sz="18" w:color="\(colors.1)"/><w:bottom w:val="single" w:sz="8" w:color="\(colors.1)"/><w:right w:val="single" w:sz="8" w:color="\(colors.1)"/></w:tblBorders><w:tblCellMar><w:top w:w="120" w:type="dxa"/><w:left w:w="180" w:type="dxa"/><w:bottom w:w="120" w:type="dxa"/><w:right w:w="180" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="9360"/></w:tblGrid><w:tr><w:trPr><w:tblHeader/></w:trPr><w:tc><w:tcPr><w:tcW w:w="9360" w:type="dxa"/><w:shd w:val="clear" w:fill="\(colors.0)"/></w:tcPr><w:p>\(linkedTitle)</w:p><w:p><w:r><w:t xml:space="preserve">\(escape(body))</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        """
    }

    private func headerXML(for document: CourseDocument) -> String { xmlHeader + "<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:pPr><w:pStyle w:val=\"Header\"/></w:pPr><w:r><w:t>SCRIB · \(escape(document.title))</w:t></w:r></w:p></w:hdr>" }
    private var footerXML: String { xmlHeader + "<w:ftr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:pPr><w:pStyle w:val=\"Footer\"/></w:pPr><w:r><w:t xml:space=\"preserve\">Scrib · Page </w:t></w:r><w:fldSimple w:instr=\"PAGE\"><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>" }
    private var settingsXML: String { xmlHeader + "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:updateFields w:val=\"true\"/><w:defaultTabStop w:val=\"720\"/><w:compat/></w:settings>" }
    private var numberingXML: String { xmlHeader + "<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"•\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"540\" w:hanging=\"270\"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>" }

    private var stylesXML: String { xmlHeader + """
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/><w:lang w:val="fr-FR"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:rPr><w:color w:val="172033"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:after="100"/></w:pPr><w:rPr><w:b/><w:sz w:val="54"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:after="240"/></w:pPr><w:rPr><w:sz w:val="26"/><w:color w:val="667085"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Kicker"><w:name w:val="Kicker"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:after="40"/></w:pPr><w:rPr><w:b/><w:caps/><w:sz w:val="19"/><w:color w:val="355AF3"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="300" w:after="160"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="2E5AAC"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="540" w:hanging="270"/><w:spacing w:after="80"/></w:pPr></w:style>
      <w:style w:type="paragraph" w:styleId="Metadata"><w:name w:val="Metadata"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:after="40"/></w:pPr><w:rPr><w:sz w:val="20"/><w:color w:val="475467"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Disclaimer"><w:name w:val="Disclaimer"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="180"/><w:shd w:val="clear" w:fill="EEF2FF"/><w:ind w:left="160" w:right="160"/></w:pPr><w:rPr><w:i/><w:sz w:val="18"/><w:color w:val="3448A4"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="TOC1"><w:name w:val="toc 1"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="240"/><w:spacing w:after="60"/></w:pPr></w:style>
      <w:style w:type="paragraph" w:styleId="Source"><w:name w:val="Source"/><w:basedOn w:val="Normal"/><w:rPr><w:sz w:val="20"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="TableCaption"><w:name w:val="Table Caption"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="120" w:after="80"/></w:pPr><w:rPr><w:b/><w:sz w:val="20"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="FigureCaption"><w:name w:val="Figure Caption"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/><w:spacing w:after="140"/></w:pPr><w:rPr><w:i/><w:sz w:val="19"/><w:color w:val="667085"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Header"><w:name w:val="header"/><w:basedOn w:val="Normal"/><w:rPr><w:sz w:val="17"/><w:color w:val="98A2B3"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="right"/></w:pPr><w:rPr><w:sz w:val="17"/><w:color w:val="98A2B3"/></w:rPr></w:style>
      <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="355AF3"/><w:u w:val="single"/></w:rPr></w:style>
    </w:styles>
    """ }

    private var xmlHeader: String { "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" }
    private func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
    private func escapeAttribute(_ value: String) -> String { escape(value).replacingOccurrences(of: "\"", with: "&quot;") }
    private static func timestamp(_ seconds: TimeInterval) -> String { let value = max(Int(seconds.rounded()), 0); return String(format: "%02d:%02d", value / 60, value % 60) }
    private static func iso8601String(from date: Date) -> String { let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]; formatter.timeZone = TimeZone(secondsFromGMT: 0); return formatter.string(from: date) }
    private static func frenchDateString(from date: Date) -> String { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_FR"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "dd/MM/yyyy"; return formatter.string(from: date) }
}
