import Foundation
import ScribApplication
import ScribDomain

public struct SimulatedCloudGenerationAdapter: AICloudGenerating, Sendable {
    public init() {}

    public func generate(
        _ request: AIProviderGenerationRequest,
        credential: String?
    ) async throws -> AIProviderGenerationResponse {
        let envelope = CourseGenerationEnvelope(
            courseID: request.courseID,
            documents: [
                GeneratedCourseDocument(
                    kind: .fullCourse,
                    title: "Cours structuré — simulation",
                    subtitle: "Génération locale sans appel API",
                    metadata: [.init(label: "Modèle", value: request.modelID)],
                    sections: [
                        .init(title: "Synthèse", blocks: [
                            .init(
                                type: .paragraph,
                                text: "Le banc d’essai a reçu la transcription et les supports fictifs, puis validé le contrat Scrib 1.0."
                            )
                        ])
                    ]
                ),
                GeneratedCourseDocument(
                    kind: .revisionSheet,
                    title: "Fiche de révision — simulation",
                    subtitle: "Résultat déterministe",
                    metadata: [.init(label: "Coût", value: "0 USD")],
                    sections: [
                        .init(title: "À retenir", blocks: [
                            .init(type: .bullets, items: [
                                "La confidentialité est vérifiée avant l’adaptateur.",
                                "Le JSON est validé avant le rendu Word.",
                                "La simulation ne contacte aucun service externe."
                            ])
                        ])
                    ]
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        return AIProviderGenerationResponse(
            payload: data,
            usage: AIProviderUsage(
                providerRequestID: "simulated-\(request.idempotencyKey.prefix(12))",
                inputTokens: max(request.input.utf8.count / 4, 1),
                outputTokens: max(data.count / 4, 1)
            )
        )
    }
}
