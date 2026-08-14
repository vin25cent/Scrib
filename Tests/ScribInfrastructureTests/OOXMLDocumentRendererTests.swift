import Foundation
import Testing
import ScribDomain
@testable import ScribInfrastructure

struct OOXMLDocumentRendererTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_787_054_400)

    @Test func packageIsDeterministicAndContainsRequiredParts() throws {
        let renderer = OOXMLDocumentRenderer()
        let document = fixture()

        let first = try renderer.data(for: document)
        let second = try renderer.data(for: document)

        #expect(first == second)
        #expect(Array(first.prefix(4)) == [0x50, 0x4b, 0x03, 0x04])
        let raw = String(decoding: first, as: UTF8.self)
        #expect(raw.contains("[Content_Types].xml"))
        #expect(raw.contains("word/document.xml"))
        #expect(raw.contains("word/styles.xml"))
        #expect(raw.contains("word/numbering.xml"))
    }

    @Test func rendererEscapesTextAndAddsTimestamp() throws {
        let data = try OOXMLDocumentRenderer().data(for: fixture())
        let raw = String(decoding: data, as: UTF8.self)

        #expect(raw.contains("Cellule &amp; tissus"))
        #expect(raw.contains("Audio 02:05"))
        #expect(raw.contains("w:tblW w:w=\"9360\" w:type=\"dxa\""))
        #expect(raw.contains("scrib://audio?t=125"))
        #expect(raw.contains("w:pgSz w:w=\"11906\" w:h=\"16838\""))
        #expect(raw.contains("w:pgMar w:top=\"1273\" w:right=\"1273\""))
    }

    @Test func rendererAddsStaticTOCTablesAndAccessibleEmbeddedImages() throws {
        let raw = String(decoding: try OOXMLDocumentRenderer().data(for: fixture()), as: UTF8.self)
        #expect(raw.contains("w:anchor=\"section_1\""))
        #expect(raw.contains("w:bookmarkStart w:id=\"1\" w:name=\"section_1\""))
        #expect(raw.contains("<w:tblHeader/>"))
        #expect(raw.contains("<w:gridCol w:w=\"3120\"/>"))
        #expect(raw.contains("word/media/image1.png"))
        #expect(raw.contains("relationships/image"))
        #expect(raw.contains("descr=\"Schéma synthétique de test\""))
        #expect(!raw.contains("<w:trHeight"))
    }

    @Test func rendererRejectsMissingImageAsset() {
        var document = fixture()
        document.imageAssets = []
        #expect(throws: OOXMLDocumentRenderer.RenderingError.missingImageAsset("schema")) {
            try OOXMLDocumentRenderer().data(for: document)
        }
    }

    @Test func longAdversarialCourseRemainsDeterministicAndEscaped() throws {
        var document = fixture()
        document.sections = (1...80).map { index in
            .init(title: "Section \(index) <script>", blocks: [.paragraph(String(repeating: "Cours & données. ", count: 50))])
        }
        let renderer = OOXMLDocumentRenderer()
        let first = try renderer.data(for: document)
        #expect(first == (try renderer.data(for: document)))
        let raw = String(decoding: first, as: UTF8.self)
        #expect(raw.contains("Section 80 &lt;script&gt;"))
        #expect(!raw.contains("Section 80 <script>"))
    }

    private func fixture() -> CourseDocument {
        CourseDocument(
            kind: .fullCourse,
            title: "Cellule & tissus",
            subtitle: "UE 2.1",
            metadata: [.init(label: "Semestre", value: "S1")],
            sections: [
                .init(
                    title: "Notions",
                    blocks: [
                        .paragraph("Un paragraphe."),
                        .bullets(["Premier", "Deuxième"]),
                        .table(.init(headers: ["Colonne A", "Colonne B", "Colonne C"], rows: [["A", "B", "C"]])),
                        .figure(.init(assetID: "schema", caption: "Figure de test", altText: "Schéma synthétique de test", widthPoints: 144)),
                        .callout(
                            kind: .uncertainty,
                            title: "À vérifier",
                            body: "Passage incertain.",
                            audioTimestamp: 125
                        )
                    ]
                )
            ],
            imageAssets: [
                .init(
                    id: "schema",
                    format: .png,
                    widthPixels: 1,
                    heightPixels: 1,
                    data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
                )
            ],
            generatedAt: fixedDate
        )
    }
}
