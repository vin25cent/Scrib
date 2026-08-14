import Foundation
import ScribApplication
import ScribDomain

public struct OOXMLDocumentRenderer: StructuredDocumentRendering, Sendable {
    public init() {}

    public func render(_ document: CourseDocument, to destination: URL) throws {
        let package = try buildPackage(for: document)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try package.write(to: destination, options: .atomic)
    }

    public func data(for document: CourseDocument) throws -> Data {
        try buildPackage(for: document)
    }

    private func buildPackage(for document: CourseDocument) throws -> Data {
        let sourceRelationships = document.sources.enumerated().map { index, source in
            SourceRelationship(id: "rId\(index + 3)", source: source)
        }
        let entries = [
            entry("[Content_Types].xml", contentTypes),
            entry("_rels/.rels", rootRelationships),
            entry("docProps/app.xml", appProperties),
            entry("docProps/core.xml", coreProperties(for: document)),
            entry("word/_rels/document.xml.rels", documentRelationships(sourceRelationships)),
            entry("word/document.xml", documentXML(document, relationships: sourceRelationships)),
            entry("word/footer1.xml", footerXML),
            entry("word/header1.xml", headerXML(for: document)),
            entry("word/numbering.xml", numberingXML),
            entry("word/settings.xml", settingsXML),
            entry("word/styles.xml", stylesXML)
        ]
        return try DeterministicZIPArchive().makeArchive(entries: entries)
    }

    private func entry(_ path: String, _ value: String) -> DeterministicZIPArchive.Entry {
        DeterministicZIPArchive.Entry(path: path, data: Data(value.utf8))
    }

    private struct SourceRelationship {
        var id: String
        var source: CourseDocumentSource
    }

    private var contentTypes: String {
        xmlHeader + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
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

    private var rootRelationships: String {
        xmlHeader + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private var appProperties: String {
        xmlHeader + """
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>Scrib</Application><AppVersion>0.1</AppVersion>
        </Properties>
        """
    }

    private func coreProperties(for document: CourseDocument) -> String {
        let date = Self.iso8601String(from: document.generatedAt)
        return xmlHeader + """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escape(document.title))</dc:title>
          <dc:creator>Scrib</dc:creator><cp:lastModifiedBy>Scrib</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(date)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(date)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private func documentRelationships(_ sources: [SourceRelationship]) -> String {
        let hyperlinks = sources.map {
            "<Relationship Id=\"\($0.id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(escapeAttribute($0.source.url.absoluteString))\" TargetMode=\"External\"/>"
        }.joined()
        return xmlHeader + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
          \(hyperlinks)
        </Relationships>
        """
    }

    private func documentXML(
        _ document: CourseDocument,
        relationships: [SourceRelationship]
    ) -> String {
        var body = titleBlock(document)
        for section in document.sections {
            body += paragraph(section.title, style: "Heading1")
            for block in section.blocks {
                switch block {
                case let .paragraph(text):
                    body += paragraph(text)
                case let .bullets(items):
                    body += items.map(bullet).joined()
                case let .callout(kind, title, text, audioTimestamp):
                    body += callout(kind: kind, title: title, body: text, audioTimestamp: audioTimestamp)
                }
            }
        }
        if !relationships.isEmpty {
            body += paragraph("Sources et vérifications", style: "Heading1")
            for relationship in relationships {
                let source = relationship.source
                let verified = Self.frenchDateString(from: source.verifiedAt)
                body += """
                <w:p><w:pPr><w:pStyle w:val="Source"/></w:pPr>
                  <w:r><w:rPr><w:b/></w:rPr><w:t>\(escape(source.authority)) - </w:t></w:r>
                  <w:hyperlink r:id="\(relationship.id)"><w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr><w:t>\(escape(source.title))</w:t></w:r></w:hyperlink>
                  <w:r><w:t xml:space="preserve"> (vérifié le \(escape(verified)))</w:t></w:r>
                </w:p>
                """
            }
        }
        body += """
        <w:sectPr>
          <w:headerReference w:type="default" r:id="rId1"/><w:footerReference w:type="default" r:id="rId2"/>
          <w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
          <w:cols w:space="708"/><w:docGrid w:linePitch="360"/>
        </w:sectPr>
        """
        return xmlHeader + """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <w:body>\(body)</w:body>
        </w:document>
        """
    }

    private func titleBlock(_ document: CourseDocument) -> String {
        var result = paragraph(document.kind == .fullCourse ? "COURS STRUCTURÉ" : "FICHE DE RÉVISION", style: "Kicker")
        result += paragraph(document.title, style: "Title")
        result += paragraph(document.subtitle, style: "Subtitle")
        for item in document.metadata {
            result += """
            <w:p><w:pPr><w:pStyle w:val="Metadata"/></w:pPr>
              <w:r><w:rPr><w:b/></w:rPr><w:t>\(escape(item.label)) : </w:t></w:r><w:r><w:t>\(escape(item.value))</w:t></w:r>
            </w:p>
            """
        }
        result += paragraph("Document de démonstration généré localement par Scrib. Le contenu est fictif et ne constitue pas une référence médicale.", style: "Disclaimer")
        return result
    }

    private func paragraph(_ text: String, style: String = "Normal") -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r></w:p>"
    }

    private func bullet(_ text: String) -> String {
        """
        <w:p><w:pPr><w:pStyle w:val="ListBullet"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t xml:space="preserve">\(escape(text))</w:t></w:r></w:p>
        """
    }

    private func callout(
        kind: CourseDocumentCalloutKind,
        title: String,
        body: String,
        audioTimestamp: TimeInterval?
    ) -> String {
        let fill: String
        let accent: String
        switch kind {
        case .information: (fill, accent) = ("F4F6F9", "1F3A5F")
        case .uncertainty: (fill, accent) = ("FFF8E1", "7A5A00")
        case .medicalImportance: (fill, accent) = ("FDECEC", "9B1C1C")
        case .scientificUpdate: (fill, accent) = ("EAF4EE", "276749")
        }
        let timestamp = audioTimestamp.map { " - Audio \(Self.timestamp($0))" } ?? ""
        return """
        <w:tbl><w:tblPr><w:tblW w:w="9360" w:type="dxa"/><w:tblInd w:w="120" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblBorders><w:top w:val="single" w:sz="8" w:color="\(accent)"/><w:left w:val="single" w:sz="18" w:color="\(accent)"/><w:bottom w:val="single" w:sz="8" w:color="\(accent)"/><w:right w:val="single" w:sz="8" w:color="\(accent)"/><w:insideH w:val="none"/><w:insideV w:val="none"/></w:tblBorders><w:tblCellMar><w:top w:w="120" w:type="dxa"/><w:left w:w="180" w:type="dxa"/><w:bottom w:w="120" w:type="dxa"/><w:right w:w="180" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w="9360"/></w:tblGrid>
          <w:tr><w:tc><w:tcPr><w:tcW w:w="9360" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="\(fill)"/></w:tcPr>
            <w:p><w:pPr><w:spacing w:before="0" w:after="60"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="\(accent)"/></w:rPr><w:t>\(escape(title + timestamp))</w:t></w:r></w:p>
            <w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="300" w:lineRule="auto"/></w:pPr><w:r><w:t xml:space="preserve">\(escape(body))</w:t></w:r></w:p>
          </w:tc></w:tr>
        </w:tbl><w:p><w:pPr><w:spacing w:before="0" w:after="80"/></w:pPr></w:p>
        """
    }

    private func headerXML(for document: CourseDocument) -> String {
        xmlHeader + """
        <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pStyle w:val="Header"/></w:pPr><w:r><w:t>SCRIB  ·  \(escape(document.title))</w:t></w:r></w:p></w:hdr>
        """
    }

    private var footerXML: String {
        xmlHeader + """
        <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:p><w:pPr><w:pStyle w:val="Footer"/></w:pPr><w:r><w:t xml:space="preserve">Scrib  ·  Page </w:t></w:r><w:fldSimple w:instr="PAGE"><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>
        """
    }

    private var settingsXML: String {
        xmlHeader + """
        <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:updateFields w:val="true"/><w:defaultTabStop w:val="720"/><w:compat/></w:settings>
        """
    }

    private var numberingXML: String {
        xmlHeader + """
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="540"/></w:tabs><w:spacing w:after="80" w:line="300" w:lineRule="auto"/><w:ind w:left="540" w:hanging="270"/></w:pPr><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/></w:rPr></w:lvl></w:abstractNum>
          <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
        </w:numbering>
        """
    }

    private var stylesXML: String {
        xmlHeader + """
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="fr-FR"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="0" w:after="120" w:line="300" w:lineRule="auto"/></w:pPr><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/><w:color w:val="172033"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Subtitle"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="0" w:after="100"/></w:pPr><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:b/><w:sz w:val="54"/><w:color w:val="172033"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:next w:val="Metadata"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="0" w:after="240"/></w:pPr><w:rPr><w:sz w:val="26"/><w:color w:val="667085"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Kicker"><w:name w:val="Kicker"/><w:basedOn w:val="Normal"/><w:next w:val="Title"/><w:pPr><w:keepNext/><w:spacing w:before="0" w:after="40"/></w:pPr><w:rPr><w:b/><w:caps/><w:sz w:val="19"/><w:color w:val="355AF3"/><w:spacing w:val="24"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:uiPriority w:val="9"/><w:pPr><w:keepNext/><w:keepLines/><w:pageBreakBefore w:val="0"/><w:spacing w:before="360" w:after="200"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="2E74B5"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="280" w:after="140"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="2E74B5"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="200" w:after="100"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/><w:color w:val="1F4D78"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="80" w:line="300" w:lineRule="auto"/><w:ind w:left="540" w:hanging="270"/></w:pPr></w:style>
          <w:style w:type="paragraph" w:styleId="Metadata"><w:name w:val="Metadata"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="0" w:after="40"/></w:pPr><w:rPr><w:sz w:val="20"/><w:color w:val="475467"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Disclaimer"><w:name w:val="Disclaimer"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="180" w:after="120"/><w:shd w:val="clear" w:fill="EEF2FF"/><w:ind w:left="160" w:right="160"/></w:pPr><w:rPr><w:i/><w:sz w:val="18"/><w:color w:val="3448A4"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Source"><w:name w:val="Source"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="80" w:after="80"/></w:pPr><w:rPr><w:sz w:val="20"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Header"><w:name w:val="header"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:rPr><w:sz w:val="17"/><w:color w:val="98A2B3"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="right"/><w:spacing w:before="0" w:after="0"/></w:pPr><w:rPr><w:sz w:val="17"/><w:color w:val="98A2B3"/></w:rPr></w:style>
          <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:unhideWhenUsed/><w:rPr><w:color w:val="355AF3"/><w:u w:val="single"/></w:rPr></w:style>
        </w:styles>
        """
    }

    private var xmlHeader: String { "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        escape(value).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func frenchDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }
}
