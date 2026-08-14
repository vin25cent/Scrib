import Foundation
import Testing
import ScribDomain
@testable import ScribApplication

struct CourseGenerationValidatorTests {
    private let courseID = CourseID(rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
    private let date = Date(timeIntervalSince1970: 1_787_054_400)

    @Test func validVersionedEnvelopeRoundTripsAndConverts() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoded = try CourseGenerationValidator().decodeAndValidate(encoder.encode(validEnvelope()), expectedCourseID: courseID)
        let documents = try CourseGenerationValidator().makeDocuments(from: decoded, generatedAt: date)
        #expect(decoded.schemaVersion == "1.0")
        #expect(documents.map(\.kind) == [.fullCourse, .revisionSheet])
        #expect(documents[0].sources.first?.id == "who-cell")
        #expect(documents[0].sections[0].blocks.count == 3)
    }

    @Test func rejectsUntrustedSourcesUnknownReferencesAndMissingAudioTimestamp() {
        var envelope = validEnvelope()
        envelope.sources[0].canonicalURL = "https://who.int.example.org/faux"
        envelope.documents[0].sections[0].blocks[0].sourceIDs = ["absente"]
        envelope.documents[0].sections[0].blocks[2].callout?.audioTimestampSeconds = nil
        let issues = CourseGenerationValidator().validate(envelope, expectedCourseID: courseID)
        #expect(issues.contains { $0.path.contains("canonicalURL") })
        #expect(issues.contains { $0.message.contains("Source inconnue") })
        #expect(issues.contains { $0.path.contains("audioTimestampSeconds") })
    }

    @Test func rejectsWrongVersionDuplicateDocumentAndRaggedTable() {
        var envelope = validEnvelope()
        envelope.schemaVersion = "2.0"
        envelope.documents[1].kind = .fullCourse
        envelope.documents[0].sections[0].blocks[1].table?.rows = [["une seule cellule"]]
        let issues = CourseGenerationValidator().validate(envelope)
        #expect(issues.contains { $0.path == "schemaVersion" })
        #expect(issues.contains { $0.path == "documents" })
        #expect(issues.contains { $0.path.contains("table.rows") })
    }

    @Test func rejectsMalformedAndOversizedPayloads() {
        let strict = CourseGenerationValidator(policy: .init(maximumPayloadBytes: 8))
        #expect(throws: CourseGenerationDecodingError.self) { try strict.decodeAndValidate(Data(repeating: 65, count: 9)) }
        #expect(throws: CourseGenerationDecodingError.self) { try CourseGenerationValidator().decodeAndValidate(Data("{".utf8)) }
    }

    @Test func rejectsUnknownInjectedPropertiesAndExcessiveCourseLength() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(validEnvelope())) as? [String: Any])
        json["promptInjection"] = "ignore les règles"
        #expect(throws: CourseGenerationDecodingError.self) {
            try CourseGenerationValidator().decodeAndValidate(JSONSerialization.data(withJSONObject: json))
        }

        var envelope = validEnvelope()
        envelope.documents[0].sections = (0...80).map { .init(title: "Section \($0)", blocks: [.init(type: .paragraph, text: "Contenu")]) }
        #expect(CourseGenerationValidator().validate(envelope).contains { $0.path == "documents[0].sections" })
    }

    private func validEnvelope() -> CourseGenerationEnvelope {
        let source = GeneratedCourseSource(id: "who-cell", authority: "OMS", title: "Cellule", canonicalURL: "https://www.who.int/fr", verifiedAt: date)
        let blocks: [GeneratedCourseBlock] = [
            .init(type: .paragraph, text: "Une cellule.", sourceIDs: ["who-cell"]),
            .init(type: .table, table: .init(caption: "Comparaison", headers: ["Élément", "Rôle"], rows: [["Noyau", "Information"]], columnWidthWeights: [1, 2])),
            .init(type: .callout, callout: .init(kind: .uncertainty, title: "À confirmer", body: "Terme entendu.", audioTimestampSeconds: 12))
        ]
        return CourseGenerationEnvelope(courseID: courseID, documents: [
            .init(kind: .fullCourse, title: "Cellule", subtitle: "UE 2.1", metadata: [], sections: [.init(title: "Notions", blocks: blocks)]),
            .init(kind: .revisionSheet, title: "Cellule", subtitle: "Révision", metadata: [], sections: [.init(title: "Essentiel", blocks: [.init(type: .bullets, items: ["Point clé"])])])
        ], sources: [source])
    }
}
