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
                        .callout(
                            kind: .uncertainty,
                            title: "À vérifier",
                            body: "Passage incertain.",
                            audioTimestamp: 125
                        )
                    ]
                )
            ],
            generatedAt: fixedDate
        )
    }
}
