import Foundation
import ScribDomain
import Testing
@testable import ScribInfrastructure

@MainActor
struct LocalSupportDocumentStoreTests {
    @Test func importsPersistsAndDeletesSupport() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib-support-test-\(UUID().uuidString)", isDirectory: true)
        let source = temporary.appendingPathComponent("input/Support enseignant.docx")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("document fictif".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let store = try LocalSupportDocumentStore(rootDirectory: temporary.appendingPathComponent("store"))
        let imported = try store.importDocument(from: source)
        #expect(imported.kind == .word)
        #expect(imported.originalFileName == "Support enseignant.docx")
        #expect(imported.localURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)

        let reopened = try LocalSupportDocumentStore(rootDirectory: temporary.appendingPathComponent("store"))
        #expect(reopened.documents().map(\.id) == [imported.id])
        try reopened.deleteDocument(id: imported.id)
        #expect(reopened.documents().isEmpty)
    }
}
