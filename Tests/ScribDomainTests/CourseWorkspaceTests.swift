import Foundation
import Testing
@testable import ScribDomain

struct CourseWorkspaceTests {
    @Test func supportManifestFromBeforeExtractionStillDecodes() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "originalFileName": "support.docx",
          "kind": "word",
          "byteCount": 42,
          "importedAt": 0
        }
        """

        let document = try JSONDecoder().decode(SupportDocument.self, from: Data(json.utf8))

        #expect(document.id == id)
        #expect(document.extraction == nil)
        #expect(document.extractionFailure == nil)
    }
}
