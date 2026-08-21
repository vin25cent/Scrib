import Foundation

public struct TranscriptionGlossary: Equatable, Codable, Sendable {
    public var globalTerms: [String]
    public var courseTerms: [String]

    public init(globalTerms: [String] = [], courseTerms: [String] = []) {
        let normalizedGlobalTerms = Self.uniqueTerms(globalTerms)
        let globalKeys = Set(normalizedGlobalTerms.map(Self.comparisonKey))
        self.globalTerms = normalizedGlobalTerms
        self.courseTerms = Self.uniqueTerms(courseTerms)
            .filter { !globalKeys.contains(Self.comparisonKey($0)) }
    }

    public var allTerms: [String] { globalTerms + courseTerms }

    public static let minimalMedical = TranscriptionGlossary(globalTerms: [
        "IFSI", "milligramme", "gramme", "microgramme", "millilitre", "posologie"
    ])

    private static func uniqueTerms(_ terms: [String]) -> [String] {
        var seen: Set<String> = []
        return terms.compactMap { raw in
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, term.count <= 80 else { return nil }
            let key = comparisonKey(term)
            guard seen.insert(key).inserted else { return nil }
            return term
        }
    }

    private static func comparisonKey(_ term: String) -> String {
        term.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
    }
}

public struct LocalTranscriptionContext: Equatable, Codable, Sendable {
    public var prompt: String
    public var glossary: TranscriptionGlossary

    public init(prompt: String, glossary: TranscriptionGlossary) {
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.glossary = glossary
    }
}

public enum LocalTranscriptionContextBuilder {
    public static let maximumPromptCharacters = 900
    public static let maximumGlossaryTerms = 40

    public static func build(
        course: Course,
        globalGlossary: [String] = TranscriptionGlossary.minimalMedical.globalTerms,
        courseGlossary: [String] = [],
        supportCandidateTerms: [String] = []
    ) -> LocalTranscriptionContext {
        let glossary = TranscriptionGlossary(
            globalTerms: globalGlossary,
            courseTerms: Array((courseGlossary + supportCandidateTerms).prefix(maximumGlossaryTerms))
        )
        var lines = [
            "Cours IFSI, \(course.semester.displayName), \(course.teachingUnit.displayName).",
            "Titre : \(course.title).",
            "Enseignant : \(course.teacherName).",
            "Domaine : sciences infirmières."
        ]
        if !glossary.allTerms.isEmpty {
            lines.append("Vocabulaire probable : \(glossary.allTerms.prefix(maximumGlossaryTerms).joined(separator: ", ")).")
        }
        let prompt = lines.joined(separator: "\n")
        return LocalTranscriptionContext(
            prompt: String(prompt.prefix(maximumPromptCharacters)),
            glossary: glossary
        )
    }
}

/// Extracts a small candidate list from already-local teacher support text.
/// Candidates still need user/course selection before they enter the prompt.
public enum SupportGlossaryCandidateExtractor {
    public static func candidates(
        from documents: [SupportDocumentExtraction],
        maximumCount: Int = 30
    ) -> [String] {
        let text = documents.map(\.plainText).joined(separator: "\n")
        let rawWords = text.split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "’" && $0 != "'" }
            .map(String.init)
        let stopWords: Set<String> = [
            "alors", "après", "avec", "avoir", "cette", "comme", "dans", "des", "donc",
            "elle", "entre", "être", "pour", "plus", "sans", "sont", "sur", "une", "vous"
        ]
        var counts: [String: (display: String, count: Int)] = [:]
        for word in rawWords {
            let normalized = word.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "fr_FR")
            )
            guard normalized.count >= 4, !stopWords.contains(normalized) else { continue }
            let looksSpecialized = word == word.uppercased() || word.count >= 7 || word.contains("-")
            guard looksSpecialized else { continue }
            let previous = counts[normalized]
            counts[normalized] = (previous?.display ?? word, (previous?.count ?? 0) + 1)
        }
        return counts.values
            .filter { $0.count >= 2 || $0.display == $0.display.uppercased() }
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.display.localizedCaseInsensitiveCompare(rhs.display) == .orderedAscending : lhs.count > rhs.count
            }
            .prefix(max(maximumCount, 0))
            .map(\.display)
    }
}

public enum TranscriptionReviewReason: String, Equatable, Codable, Sendable {
    case lowConfidence
    case lowConfidenceCriticalNumber
}

public enum TranscriptionReviewPolicy {
    /// WhisperKit exposes model probabilities, not a calibrated medical accuracy score.
    public static let lowConfidenceThreshold = 0.50

    public static func reasons(for passage: RecognizedTranscriptionPassage) -> [TranscriptionReviewReason] {
        let lowPassageConfidence = passage.confidence.map { $0 < lowConfidenceThreshold } ?? false
        let lowWordConfidence = passage.words.contains { word in
            word.probability.map { $0 < lowConfidenceThreshold } ?? false
        }
        let containsCriticalNumber = MedicalNumericExpressionDetector.containsCriticalExpression(in: passage.text)
        if containsCriticalNumber && (lowPassageConfidence || lowWordConfidence) {
            return [.lowConfidenceCriticalNumber]
        }
        return lowPassageConfidence ? [.lowConfidence] : []
    }
}

public enum MedicalNumericExpressionDetector {
    private static let pattern = #"(?i)(?:\b\d+(?:[\s.,]\d+)?\s*(?:mg|g|kg|µg|mcg|ml|l|mg/kg|µg/kg)\b|\b\d+\s*(?:à|a|-)\s*\d+\s*(?:prises?|heures?|jours?)\b|\b\d+\s*(?:heures?|jours?|prises?)\b)"#

    public static func containsCriticalExpression(in text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }
}

public enum TranscriptTransformationKind: String, Equatable, Codable, Sendable {
    case whisperControlTokenRemoval
    case boundaryDeduplication
}

public struct TranscriptTransformation: Equatable, Codable, Sendable {
    public var passageID: UUID
    public var kind: TranscriptTransformationKind
    public var originalText: String
    public var resultingText: String
    public var originalStartTime: TimeInterval
    public var resultingStartTime: TimeInterval

    public init(
        passageID: UUID,
        kind: TranscriptTransformationKind,
        originalText: String,
        resultingText: String,
        originalStartTime: TimeInterval,
        resultingStartTime: TimeInterval
    ) {
        self.passageID = passageID
        self.kind = kind
        self.originalText = originalText
        self.resultingText = resultingText
        self.originalStartTime = originalStartTime
        self.resultingStartTime = resultingStartTime
    }
}
