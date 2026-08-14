import Foundation
import Testing
import ScribDomain
@testable import ScribInfrastructure

struct WhisperKitResultMapperTests {
    @Test func preservesSegmentAndWordTimestampsWithTimelineOffset() {
        let sourceID = UUID()
        let mapped = WhisperKitResultMapper().map(
            [
                .init(
                    start: 1.5,
                    end: 3.0,
                    text: " La cellule ",
                    averageLogProbability: -0.2,
                    words: [.init(text: "cellule", start: 2, end: 2.5, probability: 0.8)]
                )
            ],
            sourceSegmentID: sourceID,
            timelineOffset: 10
        )
        #expect(mapped.count == 1)
        #expect(mapped[0].sourceSegmentID == sourceID)
        #expect(mapped[0].startTime == 11.5)
        #expect(mapped[0].endTime == 13)
        #expect(mapped[0].text == "La cellule")
        #expect(mapped[0].words[0].startTime == 12)
        #expect(abs((mapped[0].confidence ?? 0) - exp(-0.2)) < 0.0001)
    }
}
