import Foundation
import ScribDomain

public struct WhisperKitWordMappingInput: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
    public var probability: Double?

    public init(text: String, start: Double, end: Double, probability: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.probability = probability
    }
}

public struct WhisperKitSegmentMappingInput: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
    public var averageLogProbability: Double?
    public var words: [WhisperKitWordMappingInput]

    public init(
        start: Double,
        end: Double,
        text: String,
        averageLogProbability: Double? = nil,
        words: [WhisperKitWordMappingInput] = []
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.averageLogProbability = averageLogProbability
        self.words = words
    }
}

public struct WhisperKitResultMapper: Sendable {
    public init() {}

    public func map(
        _ inputs: [WhisperKitSegmentMappingInput],
        sourceSegmentID: UUID,
        timelineOffset: TimeInterval
    ) -> [RecognizedTranscriptionPassage] {
        inputs.compactMap { input in
            let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let confidence = input.averageLogProbability.map { min(max(exp($0), 0), 1) }
            return RecognizedTranscriptionPassage(
                sourceSegmentID: sourceSegmentID,
                startTime: timelineOffset + max(input.start, 0),
                endTime: timelineOffset + max(input.end, input.start, 0),
                text: text,
                confidence: confidence,
                words: input.words.map {
                    RecognizedTranscriptionWord(
                        text: $0.text,
                        startTime: timelineOffset + max($0.start, 0),
                        endTime: timelineOffset + max($0.end, $0.start, 0),
                        probability: $0.probability
                    )
                }
            )
        }
    }
}
