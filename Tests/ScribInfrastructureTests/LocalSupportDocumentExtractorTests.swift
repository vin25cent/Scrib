import Foundation
import ScribApplication
import ScribDomain
import Testing
@testable import ScribInfrastructure

struct LocalSupportDocumentExtractorTests {
    @Test func parsesWordHeadingsListsParagraphsAndTablesInOrder() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Pharmacologie</w:t></w:r></w:p>
            <w:p><w:r><w:t>Introduction au cours.</w:t></w:r></w:p>
            <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/></w:numPr></w:pPr><w:r><w:t>Vérifier la prescription</w:t></w:r></w:p>
            <w:tbl>
              <w:tr><w:tc><w:p><w:r><w:t>Étape</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Contrôle</w:t></w:r></w:p></w:tc></w:tr>
              <w:tr><w:tc><w:p><w:r><w:t>Avant</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Identité</w:t></w:r></w:p></w:tc></w:tr>
            </w:tbl>
          </w:body>
        </w:document>
        """

        let parsed = try DOCXContentParser.parse(Data(xml.utf8))

        #expect(parsed.elements.map(\.kind) == [.heading, .paragraph, .listItem])
        #expect(parsed.elements.map(\.text) == [
            "Pharmacologie", "Introduction au cours.", "Vérifier la prescription"
        ])
        #expect(parsed.elements.first?.level == 1)
        #expect(parsed.tables == [
            SupportExtractedTable(
                order: 3,
                rows: [["Étape", "Contrôle"], ["Avant", "Identité"]]
            )
        ])
    }

    #if os(macOS)
    @Test func extractsARealOOXMLPackageAndRejectsScribOutput() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib-docx-extraction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let wordXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Support du professeur</w:t></w:r></w:p>
        </w:body></w:document>
        """
        let package = try DeterministicZIPArchive().makeArchive(entries: [
            .init(path: "word/document.xml", data: Data(wordXML.utf8)),
            .init(
                path: "docProps/core.xml",
                data: Data("<cp:coreProperties xmlns:cp=\"x\" xmlns:dc=\"y\"><dc:title>Titre fourni</dc:title><dc:creator>Dr Martin</dc:creator></cp:coreProperties>".utf8)
            )
        ])
        let supportURL = temporary.appendingPathComponent("support.docx")
        try package.write(to: supportURL)
        let extractor = LocalSupportDocumentExtractor()
        let result = try extractor.extract(
            documentID: UUID(),
            fileName: supportURL.lastPathComponent,
            kind: .word,
            from: supportURL
        )
        #expect(result.title == "Titre fourni")
        #expect(result.textElements.map(\.text) == ["Support du professeur"])

        let generatedURL = temporary.appendingPathComponent("sortie.docx")
        let generated = CourseDocument(
            kind: .fullCourse,
            title: "Sortie Scrib",
            subtitle: "Test",
            metadata: [],
            sections: []
        )
        try OOXMLDocumentRenderer().render(generated, to: generatedURL)
        #expect(throws: SupportExtractionError.generatedByScrib) {
            try extractor.extract(
                documentID: UUID(),
                fileName: generatedURL.lastPathComponent,
                kind: .word,
                from: generatedURL
            )
        }
    }
    #endif
}
