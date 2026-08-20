import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ScribApplication
import ScribDomain
import Testing
@testable import ScribInfrastructure

struct AIGenerationServiceTests {
    @Test func privacyApprovalThenGenerationIsValidatedPersistedAndIdempotent() async throws {
        let secretStore = InMemoryAISecretStore()
        let runStore = InMemoryAIGenerationRunStore()
        let orchestrator = StructuredGenerationOrchestrator(
            adapters: [.openAI: StubGenerationAdapter()],
            secretStore: secretStore,
            runStore: runStore
        )
        var request = makeRequest(profile: nonLiveTestProfile)

        do {
            _ = try await orchestrator.run(request)
            Issue.record("La confidentialité aurait dû bloquer l’essai.")
        } catch let error as AIGenerationError {
            guard case .privacyApprovalRequired = error else {
                Issue.record("Erreur inattendue : \(error)")
                return
            }
        }

        let content = request.transcript.plainText
            + "\n"
            + request.supportExtractions.map(\.plainText).joined(separator: "\n")
        request.privacyReview = PrivacyReview(
            contentFingerprint: TranscriptWorkspaceService().stableFingerprint(content),
            decision: .approved
        )
        let first = try await orchestrator.run(request)
        let second = try await orchestrator.run(request)

        #expect(first.id == second.id)
        #expect(first.documents.map(\.kind) == [.fullCourse, .revisionSheet])
        #expect(first.usage.estimatedCostUSD == 0)
        #expect(await runStore.runs().count == 1)
    }

    @Test func liveCallsRequireExplicitEnablementAndBudgetHeadroom() async throws {
        let adapter = CountingAdapter()
        let secretStore = InMemoryAISecretStore()
        let runStore = InMemoryAIGenerationRunStore()
        let orchestrator = StructuredGenerationOrchestrator(
            adapters: [.openAI: adapter],
            secretStore: secretStore,
            runStore: runStore
        )
        let expensive = AIModelProfile(
            id: "expensive",
            provider: .openAI,
            modelID: "test-model",
            displayName: "Test",
            inputPriceUSDPerMillionTokens: 1_000,
            outputPriceUSDPerMillionTokens: 1_000,
            isLive: true
        )
        var request = makeRequest(profile: expensive)
        request.privacyReview = approvedReview(for: request)

        do {
            _ = try await orchestrator.run(request)
            Issue.record("Un appel réel désactivé aurait dû être bloqué.")
        } catch let error as AIGenerationError {
            #expect(error == .liveRequestsDisabled)
        }

        request.preferences.liveRequestsEnabled = true
        request.preferences.trialBudgetUSD = 0.01
        do {
            _ = try await orchestrator.run(request)
            Issue.record("Le budget aurait dû bloquer l’appel.")
        } catch let error as AIGenerationError {
            guard case .budgetExceeded = error else {
                Issue.record("Erreur inattendue : \(error)")
                return
            }
        }
        #expect(await adapter.callCount == 0)
    }

    @Test func openAIRequestUsesStructuredOutputAndNeverEmbedsCredential() throws {
        let courseID = CourseID()
        let providerRequest = AIProviderGenerationRequest(
            courseID: courseID,
            modelID: "gpt-test",
            idempotencyKey: "idem-123",
            developerPrompt: "Règles",
            input: "Données fictives",
            maximumOutputTokens: 4_000
        )
        let request = try OpenAIResponsesRequestBuilder.makeRequest(
            providerRequest,
            endpoint: URL(string: "https://api.openai.com/v1/responses")!
        )
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let text = try #require(object["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])

        #expect(request.url?.host == "api.openai.com")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "idem-123")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)
        #expect(!String(decoding: body, as: UTF8.self).contains("sk-"))
    }

    @Test func openAIAdapterReadsMessageAfterReasoningItemAndUsage() async throws {
        let outputJSON = "{\"schemaVersion\":\"1.0\"}"
        let escapedOutput = outputJSON.replacingOccurrences(of: "\"", with: "\\\"")
        MockURLProtocol.responseData = Data("""
        {
          "id": "resp_test",
          "output": [
            {"type": "reasoning", "id": "reasoning_test"},
            {"type": "message", "content": [
              {"type": "output_text", "text": "\(escapedOutput)"}
            ]}
          ],
          "usage": {
            "input_tokens": 123,
            "output_tokens": 45,
            "input_tokens_details": {"cached_tokens": 10}
          }
        }
        """.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let adapter = OpenAIResponsesAdapter(session: URLSession(configuration: configuration))
        let request = AIProviderGenerationRequest(
            courseID: CourseID(),
            modelID: "gpt-test",
            idempotencyKey: "idem",
            developerPrompt: "Règles",
            input: "Fictif",
            maximumOutputTokens: 1_000
        )

        let response = try await adapter.generate(request, credential: "sk-test-not-real")

        #expect(String(decoding: response.payload, as: UTF8.self) == outputJSON)
        #expect(response.usage.providerRequestID == "resp_test")
        #expect(response.usage.inputTokens == 123)
        #expect(response.usage.cachedInputTokens == 10)
        #expect(response.usage.outputTokens == 45)
        #expect(MockURLProtocol.authorizationHeader == "Bearer sk-test-not-real")
        MockURLProtocol.responseData = nil
        MockURLProtocol.authorizationHeader = nil
    }

    @Test func completedRunSurvivesStoreReopening() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib-ai-runs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let secretStore = InMemoryAISecretStore()
        let firstStore = try LocalAIGenerationRunStore(rootDirectory: temporary)
        let orchestrator = StructuredGenerationOrchestrator(
            adapters: [.openAI: StubGenerationAdapter()],
            secretStore: secretStore,
            runStore: firstStore
        )
        var request = makeRequest(profile: nonLiveTestProfile)
        request.privacyReview = approvedReview(for: request)
        let completed = try await orchestrator.run(request)

        let reopened = try LocalAIGenerationRunStore(rootDirectory: temporary)
        #expect(await reopened.run(idempotencyKey: completed.idempotencyKey)?.id == completed.id)
    }

    #if os(macOS)
    @Test func macKeychainRoundTripDoesNotSynchronizeSecret() async throws {
        let service = "fr.scrib.tests.\(UUID().uuidString)"
        let store = MacKeychainSecretStore(service: service)
        defer { Task { try? await store.deleteSecret(for: .openAI) } }

        try await store.saveSecret("sk-test-only-not-a-real-secret", for: .openAI)
        #expect(try await store.hasSecret(for: .openAI))
        #expect(try await store.readSecret(for: .openAI) == "sk-test-only-not-a-real-secret")
        try await store.deleteSecret(for: .openAI)
        #expect(try await store.readSecret(for: .openAI) == nil)
    }
    #endif

    private var nonLiveTestProfile: AIModelProfile {
        AIModelProfile(
            id: "local-test-profile",
            provider: .openAI,
            modelID: "local-test-model",
            displayName: "Adaptateur de test local",
            inputPriceUSDPerMillionTokens: 0,
            outputPriceUSDPerMillionTokens: 0,
            isLive: false
        )
    }

    private func makeRequest(profile: AIModelProfile) -> AIGenerationRequest {
        let transcript = TranscriptDraft(
            courseTitle: "Pharmacologie",
            teachingUnit: "UE 2.11 — Pharmacologie et thérapeutiques",
            passages: [
                TranscriptPassage(
                    speaker: "Enseignant",
                    startTime: 0,
                    text: "Contacter patient@example.test pour le suivi du traitement.",
                    flags: [.medicalImportance]
                )
            ]
        )
        let teacher = Teacher(name: "Enseignant", recordingAuthorizationConfirmedAt: Date())
        let course = Course(
            id: transcript.courseID,
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1).first { $0.code == "2.11" }!,
            title: transcript.courseTitle,
            teacher: teacher,
            expectedDuration: .oneHour
        )
        let extraction = SupportDocumentExtraction(
            documentID: UUID(),
            sourceFileName: "Support-enseignant.docx",
            title: "Repères de pharmacologie",
            textElements: [
                .init(kind: .heading, text: "Sécurisation de l’administration", level: 1, order: 0),
                .init(kind: .listItem, text: "Vérifier la prescription.", order: 1)
            ]
        )
        return AIGenerationRequest(
            course: course,
            transcript: transcript,
            supportExtractions: [extraction],
            privacyReview: nil,
            modelProfile: profile,
            preferences: AIGenerationPreferences(selectedModelProfileID: profile.id)
        )
    }

    private func approvedReview(for request: AIGenerationRequest) -> PrivacyReview {
        let content = request.transcript.plainText
            + "\n"
            + request.supportExtractions.map(\.plainText).joined(separator: "\n")
        return PrivacyReview(
            contentFingerprint: TranscriptWorkspaceService().stableFingerprint(content),
            decision: .approved
        )
    }
}

private struct StubGenerationAdapter: AICloudGenerating {
    func generate(
        _ request: AIProviderGenerationRequest,
        credential: String?
    ) async throws -> AIProviderGenerationResponse {
        let envelope = CourseGenerationEnvelope(
            courseID: request.courseID,
            documents: [
                GeneratedCourseDocument(
                    kind: .fullCourse,
                    title: "Cours structuré",
                    subtitle: "Résultat de test",
                    metadata: [.init(label: "Modèle", value: request.modelID)],
                    sections: [
                        .init(title: "Synthèse", blocks: [
                            .init(type: .paragraph, text: "Contenu structuré validant le contrat Scrib 1.0.")
                        ])
                    ]
                ),
                GeneratedCourseDocument(
                    kind: .revisionSheet,
                    title: "Fiche de révision",
                    subtitle: "Résultat de test",
                    metadata: [],
                    sections: [
                        .init(title: "À retenir", blocks: [
                            .init(type: .bullets, items: ["Le JSON est validé avant le rendu Word."])
                        ])
                    ]
                )
            ]
        )
        let data = try JSONEncoder().encode(envelope)
        return AIProviderGenerationResponse(
            payload: data,
            usage: AIProviderUsage(
                providerRequestID: "test-request",
                inputTokens: max(request.input.utf8.count / 4, 1),
                outputTokens: max(data.count / 4, 1)
            )
        )
    }
}

private actor CountingAdapter: AICloudGenerating {
    private(set) var callCount = 0

    func generate(
        _ request: AIProviderGenerationRequest,
        credential: String?
    ) async throws -> AIProviderGenerationResponse {
        callCount += 1
        throw AIGenerationError.provider(message: "Ne devrait pas être appelé", retryable: false)
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var authorizationHeader: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.authorizationHeader = request.value(forHTTPHeaderField: "Authorization")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
