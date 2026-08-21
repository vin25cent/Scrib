import Foundation

/// Removes Whisper control tokens only from text intended for users.
/// Raw transcription structures must keep their original text.
public enum WhisperTranscriptTextNormalizer {
    public static func normalize(_ rawText: String) -> String {
        var normalized = ""
        var cursor = rawText.startIndex

        while let opening = rawText.range(
            of: "<|",
            range: cursor..<rawText.endIndex
        ), let closing = rawText.range(
            of: "|>",
            range: opening.upperBound..<rawText.endIndex
        ) {
            normalized.append(contentsOf: rawText[cursor..<opening.lowerBound])
            cursor = closing.upperBound
        }

        normalized.append(contentsOf: rawText[cursor..<rawText.endIndex])
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalize(_ draft: TranscriptDraft) -> TranscriptDraft {
        var normalizedDraft = draft
        normalizedDraft.passages = draft.passages.compactMap { passage in
            var normalizedPassage = passage
            normalizedPassage.text = normalize(passage.text)
            return normalizedPassage.text.isEmpty ? nil : normalizedPassage
        }
        return normalizedDraft
    }
}
