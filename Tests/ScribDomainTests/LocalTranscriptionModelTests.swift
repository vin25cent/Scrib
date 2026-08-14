import Foundation
import Testing
@testable import ScribDomain

struct LocalTranscriptionModelTests {
    @Test func alphaCatalogEnablesOnlyTinyAndSmall() {
        #expect(LocalTranscriptionModelCatalog.alphaModels.map(\.id) == [.tinyMultilingual, .smallMultilingual])
        #expect(LocalTranscriptionModelCatalog.descriptor(for: .tinyMultilingual)?.whisperKitVariant == "openai_whisper-tiny")
        #expect(LocalTranscriptionModelCatalog.descriptor(for: .smallMultilingual)?.estimatedDownloadBytes == 486_000_000)
        #expect(LocalTranscriptionModelCatalog.descriptor(for: .mediumMultilingual)?.isEnabledInAlpha == false)
        #expect(LocalTranscriptionModelCatalog.descriptor(for: .largeV3Turbo) != nil)
    }

    @Test func legacyTranscriptDraftStillDecodesWithoutProvenance() throws {
        let courseID = UUID()
        let json = """
        {
          "courseID": { "rawValue": "\(courseID.uuidString)" },
          "courseTitle": "Biologie",
          "teachingUnit": "UE 2.1",
          "passages": [],
          "version": 1,
          "updatedAt": 0,
          "isDemonstration": false
        }
        """
        let decoder = JSONDecoder()
        let draft = try decoder.decode(TranscriptDraft.self, from: Data(json.utf8))
        #expect(draft.transcriptionEngine == nil)
        #expect(draft.transcriptionModelID == nil)
        #expect(draft.rawTranscriptionCompletedAt == nil)
    }
}
