import Foundation

/// Formats the locally produced transcription without modifying its content.
public enum LocalTranscriptionExport {
    public static func plainText(from transcription: StoredLocalTranscription) -> String {
        let course = transcription.course
        let result = transcription.result
        var metadata = [
            "Cours : \(course.title)"
        ]

        if let teachingUnit = teachingUnitText(for: course) {
            metadata.append("UE : \(teachingUnit)")
        }

        metadata.append("Date : \(dateFormatter.string(from: course.courseDate))")
        metadata.append("Modèle : \(result.modelID.rawValue)")
        metadata.append("Version : transcription brute (tokens Whisper internes masqués)")

        if result.metrics.audioDurationSeconds > 0 {
            metadata.append("Durée : \(timestamp(result.metrics.audioDurationSeconds))")
        }

        let passages = result.passages.compactMap { passage -> String? in
            let userFacingText = WhisperTranscriptTextNormalizer.normalize(passage.text)
            guard !userFacingText.isEmpty else { return nil }
            return "[\(timestamp(passage.startTime))] \(userFacingText)"
        }

        return metadata.joined(separator: "\n")
            + (passages.isEmpty ? "" : "\n\n" + passages.joined(separator: "\n"))
    }

    /// Encodes the existing stored transcription, including raw passages, words and metrics.
    public static func jsonData(from transcription: StoredLocalTranscription) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(transcription)
    }

    public static func timestamp(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func teachingUnitText(for course: Course) -> String? {
        let code = course.teachingUnit.code
        let title = course.teachingUnit.title
        guard !code.isEmpty || !title.isEmpty else { return nil }
        if code.isEmpty { return title }
        if title.isEmpty { return "UE \(code)" }
        return course.teachingUnit.displayName
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
