import Foundation
import ScribApplication
import ScribDomain
import Testing
@testable import ScribInfrastructure

@MainActor
struct LocalSupportDocumentStoreTests {
    private struct FixtureExtractor: SupportDocumentExtracting {
        func extract(
            documentID: UUID,
            fileName: String,
            kind: SupportDocumentKind,
            from url: URL
        ) throws -> SupportDocumentExtraction {
            SupportDocumentExtraction(
                documentID: documentID,
                sourceFileName: fileName,
                title: "Support extrait",
                textElements: [.init(kind: .heading, text: "Plan du cours", level: 1, order: 0)]
            )
        }
    }

    @Test func importsPersistsAndDeletesSupport() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib-support-test-\(UUID().uuidString)", isDirectory: true)
        let source = temporary.appendingPathComponent("input/Support enseignant.docx")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("document fictif".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let store = try LocalSupportDocumentStore(
            rootDirectory: temporary.appendingPathComponent("store"),
            extractor: FixtureExtractor()
        )
        let imported = try store.importDocument(from: source)
        #expect(imported.kind == .word)
        #expect(imported.originalFileName == "Support enseignant.docx")
        #expect(imported.localURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(imported.extraction?.title == "Support extrait")

        let reopened = try LocalSupportDocumentStore(rootDirectory: temporary.appendingPathComponent("store"))
        #expect(reopened.documents().map(\.id) == [imported.id])
        #expect(reopened.documents().first?.extraction?.textElements.first?.text == "Plan du cours")
        try reopened.deleteDocument(id: imported.id)
        #expect(reopened.documents().isEmpty)
    }
}
