import Foundation
import ScribApplication
import ScribDomain
import Testing
@testable import ScribInfrastructure

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

    private final class ControlledManifestWriter: @unchecked Sendable {
        var shouldFail = false

        func write(_ data: Data, to url: URL) throws {
            if shouldFail { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        }
    }

    @Test func importsExtractsPersistsAndDeletesSupport() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib-support-test-\(UUID().uuidString)", isDirectory: true)
        let source = temporary.appendingPathComponent("input/Support enseignant.docx")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("document fictif".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let store = LocalSupportDocumentStore(
            rootDirectory: temporary.appendingPathComponent("store"),
            extractor: FixtureExtractor()
        )
        let imported = try await store.importDocument(from: source)
        #expect(imported.kind == .word)
        #expect(imported.originalFileName == "Support enseignant.docx")
        #expect(imported.localURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(imported.extraction?.title == "Support extrait")

        let reopened = LocalSupportDocumentStore(rootDirectory: temporary.appendingPathComponent("store"))
        #expect((try await reopened.documents()).map(\.id) == [imported.id])
        #expect((try await reopened.documents()).first?.extraction?.textElements.first?.text == "Plan du cours")
        try await reopened.deleteDocument(id: imported.id)
        #expect((try await reopened.documents()).isEmpty)
        #expect(imported.localURL.map { !FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func rejectsUnreadableSourceWithoutCreatingManifestEntry() async throws {
        let temporary = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = LocalSupportDocumentStore(rootDirectory: temporary.appendingPathComponent("store"))

        do {
            _ = try await store.importDocument(from: temporary.appendingPathComponent("missing.pdf"))
            Issue.record("L’import d’un fichier absent devait échouer.")
        } catch {}

        #expect((try await store.documents()).isEmpty)
    }

    @Test func reportsManifestReadError() async throws {
        let temporary = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("manifest incomplet".utf8).write(to: root.appendingPathComponent("manifest.json"))
        let store = LocalSupportDocumentStore(rootDirectory: root)

        do {
            _ = try await store.documents()
            Issue.record("Un manifeste illisible devait remonter une erreur de lecture.")
        } catch {}
    }

    @Test func rollsBackCopiedFileWhenImportManifestWriteFails() async throws {
        let temporary = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("support.pdf")
        try Data("support".utf8).write(to: source)
        let writer = ControlledManifestWriter()
        writer.shouldFail = true
        let store = LocalSupportDocumentStore(
            rootDirectory: temporary.appendingPathComponent("store"),
            manifestWriter: { data, url in try writer.write(data, to: url) }
        )

        do {
            _ = try await store.importDocument(from: source)
            Issue.record("L’import devait échouer lorsque le manifeste est indisponible.")
        } catch {}

        #expect((try await store.documents()).isEmpty)
        let storeContents = try? FileManager.default.contentsOfDirectory(
            at: temporary.appendingPathComponent("store"),
            includingPropertiesForKeys: nil
        )
        #expect(storeContents?.isEmpty != false)
    }

    @Test func restoresFileAndManifestWhenDeletionManifestWriteFails() async throws {
        let temporary = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("support.pdf")
        try Data("support".utf8).write(to: source)
        let writer = ControlledManifestWriter()
        let root = temporary.appendingPathComponent("store")
        let store = LocalSupportDocumentStore(
            rootDirectory: root,
            manifestWriter: { data, url in try writer.write(data, to: url) }
        )
        let imported = try await store.importDocument(from: source)
        writer.shouldFail = true

        do {
            try await store.deleteDocument(id: imported.id)
            Issue.record("La suppression devait échouer lorsque le manifeste est indisponible.")
        } catch {}

        #expect((try await store.documents()).map(\.id) == [imported.id])
        #expect(imported.localURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        let reopened = LocalSupportDocumentStore(rootDirectory: root)
        #expect((try await reopened.documents()).map(\.id) == [imported.id])
    }

    private func makeTemporaryDirectory() -> URL {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib-support-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        return temporary
    }
}
