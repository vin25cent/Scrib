import Foundation
import ScribDomain

public struct TranscriptBenchmarkScorer: Sendable {
    public init() {}

    public func score(
        reference: String,
        hypothesis: String,
        criticalTerms: [String] = [],
        referenceTimestamps: [TimestampedTerm] = [],
        hypothesisTimestamps: [TimestampedTerm] = []
    ) -> TranscriptAccuracyMetrics {
        let strictReference = words(in: reference, stripDiacritics: false)
        let strictHypothesis = words(in: hypothesis, stripDiacritics: false)
        let relaxedReference = words(in: reference, stripDiacritics: true)
        let relaxedHypothesis = words(in: hypothesis, stripDiacritics: true)

        return TranscriptAccuracyMetrics(
            strictWordErrorRate: errorRate(reference: strictReference, hypothesis: strictHypothesis),
            relaxedWordErrorRate: errorRate(reference: relaxedReference, hypothesis: relaxedHypothesis),
            characterErrorRate: characterErrorRate(reference: relaxedReference, hypothesis: relaxedHypothesis),
            criticalTermRecall: criticalTermRecall(terms: criticalTerms, hypothesis: relaxedHypothesis),
            meanTimestampErrorSeconds: timestampError(
                reference: referenceTimestamps,
                hypothesis: hypothesisTimestamps
            ),
            referenceWordCount: strictReference.count
        )
    }

    private func words(in text: String, stripDiacritics: Bool) -> [String] {
        var normalized = text.lowercased()
        if stripDiacritics {
            normalized = normalized.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        }
        return normalized
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) || $0 == "'" ? Character(String($0)) : " " }
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    private func errorRate(reference: [String], hypothesis: [String]) -> Double {
        guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
        return Double(editDistance(reference, hypothesis)) / Double(reference.count)
    }

    private func characterErrorRate(reference: [String], hypothesis: [String]) -> Double {
        let referenceCharacters = Array(reference.joined(separator: " "))
        let hypothesisCharacters = Array(hypothesis.joined(separator: " "))
        guard !referenceCharacters.isEmpty else { return hypothesisCharacters.isEmpty ? 0 : 1 }
        return Double(editDistance(referenceCharacters, hypothesisCharacters)) / Double(referenceCharacters.count)
    }

    private func criticalTermRecall(terms: [String], hypothesis: [String]) -> Double {
        guard !terms.isEmpty else { return 1 }
        let found = terms.filter { term in
            let tokens = words(in: term, stripDiacritics: true)
            guard !tokens.isEmpty, tokens.count <= hypothesis.count else { return false }
            return (0...(hypothesis.count - tokens.count)).contains { start in
                Array(hypothesis[start..<(start + tokens.count)]) == tokens
            }
        }.count
        return Double(found) / Double(terms.count)
    }

    private func timestampError(
        reference: [TimestampedTerm],
        hypothesis: [TimestampedTerm]
    ) -> Double? {
        guard !reference.isEmpty, !hypothesis.isEmpty else { return nil }
        let indexedReference = Dictionary(grouping: reference) {
            words(in: $0.term, stripDiacritics: true).joined(separator: " ")
        }
        let indexedHypothesis = Dictionary(grouping: hypothesis) {
            words(in: $0.term, stripDiacritics: true).joined(separator: " ")
        }

        var errors: [Double] = []
        for (term, expectedValues) in indexedReference {
            guard var available = indexedHypothesis[term] else { continue }
            available.sort { $0.seconds < $1.seconds }
            for expected in expectedValues.sorted(by: { $0.seconds < $1.seconds }) where !available.isEmpty {
                let nearestIndex = available.indices.min {
                    abs(available[$0].seconds - expected.seconds) <
                    abs(available[$1].seconds - expected.seconds)
                }!
                errors.append(abs(available[nearestIndex].seconds - expected.seconds))
                available.remove(at: nearestIndex)
            }
        }
        guard !errors.isEmpty else { return nil }
        return errors.reduce(0, +) / Double(errors.count)
    }

    private func editDistance<Element: Equatable>(_ source: [Element], _ target: [Element]) -> Int {
        if source.isEmpty { return target.count }
        if target.isEmpty { return source.count }

        var previous = Array(0...target.count)
        for (sourceIndex, sourceElement) in source.enumerated() {
            var current = Array(repeating: 0, count: target.count + 1)
            current[0] = sourceIndex + 1
            for (targetIndex, targetElement) in target.enumerated() {
                let substitution = previous[targetIndex] + (sourceElement == targetElement ? 0 : 1)
                let insertion = current[targetIndex] + 1
                let deletion = previous[targetIndex + 1] + 1
                current[targetIndex + 1] = min(substitution, insertion, deletion)
            }
            previous = current
        }
        return previous[target.count]
    }
}
