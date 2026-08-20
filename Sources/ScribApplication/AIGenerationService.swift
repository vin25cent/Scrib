import Foundation
import ScribDomain

public enum AIProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case openAI

    public var displayName: String {
        "OpenAI"
    }
}

public struct AIModelProfile: Identifiable, Codable, Sendable {
    public var id: String
    public var provider: AIProviderID
    public var modelID: String
    public var displayName: String
    public var inputPriceUSDPerMillionTokens: Double
    public var outputPriceUSDPerMillionTokens: Double
    public var pricingVerifiedAt: Date?
    public var isLive: Bool

    public init(
        id: String,
        provider: AIProviderID,
        modelID: String,
        displayName: String,
        inputPriceUSDPerMillionTokens: Double,
        outputPriceUSDPerMillionTokens: Double,
        pricingVerifiedAt: Date? = nil,
        isLive: Bool
    ) {
        self.id = id
        self.provider = provider
        self.modelID = modelID
        self.displayName = displayName
        self.inputPriceUSDPerMillionTokens = max(inputPriceUSDPerMillionTokens, 0)
        self.outputPriceUSDPerMillionTokens = max(outputPriceUSDPerMillionTokens, 0)
        self.pricingVerifiedAt = pricingVerifiedAt
        self.isLive = isLive
    }

    public func estimatedCostUSD(inputTokens: Int, outputTokens: Int) -> Double {
        let input = Double(max(inputTokens, 0)) * inputPriceUSDPerMillionTokens / 1_000_000
        let output = Double(max(outputTokens, 0)) * outputPriceUSDPerMillionTokens / 1_000_000
        return input + output
    }
}

public struct AIGenerationPreferences: Codable, Sendable {
    public var selectedModelProfileID: String
    public var trialBudgetUSD: Double
    public var maximumOutputTokens: Int
    public var liveRequestsEnabled: Bool

    public init(
        selectedModelProfileID: String = "openai-gpt-5.6-luna",
        trialBudgetUSD: Double = 8,
        maximumOutputTokens: Int = 16_000,
        liveRequestsEnabled: Bool = false
    ) {
        self.selectedModelProfileID = selectedModelProfileID
        self.trialBudgetUSD = max(trialBudgetUSD, 0)
        self.maximumOutputTokens = max(1_000, min(maximumOutputTokens, 64_000))
        self.liveRequestsEnabled = liveRequestsEnabled
    }
}

public struct AIProviderUsage: Codable, Sendable {
    public var providerRequestID: String
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int

    public init(
        providerRequestID: String,
        inputTokens: Int,
        cachedInputTokens: Int = 0,
        outputTokens: Int
    ) {
        self.providerRequestID = providerRequestID
        self.inputTokens = max(inputTokens, 0)
        self.cachedInputTokens = max(cachedInputTokens, 0)
        self.outputTokens = max(outputTokens, 0)
    }
}

public struct AIGenerationUsageRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public var idempotencyKey: String
    public var provider: AIProviderID
    public var modelID: String
    public var providerRequestID: String
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var estimatedCostUSD: Double
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        idempotencyKey: String,
        provider: AIProviderID,
        modelID: String,
        usage: AIProviderUsage,
        estimatedCostUSD: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.provider = provider
        self.modelID = modelID
        self.providerRequestID = usage.providerRequestID
        self.inputTokens = usage.inputTokens
        self.cachedInputTokens = usage.cachedInputTokens
        self.outputTokens = usage.outputTokens
        self.estimatedCostUSD = max(estimatedCostUSD, 0)
        self.createdAt = createdAt
    }
}

public struct AIProviderGenerationRequest: Sendable {
    public var courseID: CourseID
    public var modelID: String
    public var idempotencyKey: String
    public var developerPrompt: String
    public var input: String
    public var maximumOutputTokens: Int

    public init(
        courseID: CourseID,
        modelID: String,
        idempotencyKey: String,
        developerPrompt: String,
        input: String,
        maximumOutputTokens: Int
    ) {
        self.courseID = courseID
        self.modelID = modelID
        self.idempotencyKey = idempotencyKey
        self.developerPrompt = developerPrompt
        self.input = input
        self.maximumOutputTokens = maximumOutputTokens
    }
}

public struct AIProviderGenerationResponse: Sendable {
    public var payload: Data
    public var usage: AIProviderUsage

    public init(payload: Data, usage: AIProviderUsage) {
        self.payload = payload
        self.usage = usage
    }
}

public struct AIGenerationRequest: Sendable {
    public var course: Course
    public var transcript: TranscriptDraft
    public var supportExtractions: [SupportDocumentExtraction]
    public var privacyReview: PrivacyReview?
    public var modelProfile: AIModelProfile
    public var preferences: AIGenerationPreferences

    public init(
        course: Course,
        transcript: TranscriptDraft,
        supportExtractions: [SupportDocumentExtraction],
        privacyReview: PrivacyReview?,
        modelProfile: AIModelProfile,
        preferences: AIGenerationPreferences
    ) {
        self.course = course
        self.transcript = transcript
        self.supportExtractions = supportExtractions
        self.privacyReview = privacyReview
        self.modelProfile = modelProfile
        self.preferences = preferences
    }
}

public struct AIGenerationRun: Identifiable, Codable, Sendable {
    public let id: UUID
    public var courseID: CourseID
    public var idempotencyKey: String
    public var modelProfile: AIModelProfile
    public var envelope: CourseGenerationEnvelope
    public var documents: [CourseDocument]
    public var usage: AIGenerationUsageRecord
    public var completedAt: Date
    public var durationMilliseconds: Int

    public init(
        id: UUID = UUID(),
        courseID: CourseID,
        idempotencyKey: String,
        modelProfile: AIModelProfile,
        envelope: CourseGenerationEnvelope,
        documents: [CourseDocument],
        usage: AIGenerationUsageRecord,
        completedAt: Date = Date(),
        durationMilliseconds: Int = 0
    ) {
        self.id = id
        self.courseID = courseID
        self.idempotencyKey = idempotencyKey
        self.modelProfile = modelProfile
        self.envelope = envelope
        self.documents = documents
        self.usage = usage
        self.completedAt = completedAt
        self.durationMilliseconds = max(durationMilliseconds, 0)
    }

    public var sectionCount: Int {
        var total = 0
        for document in documents {
            total += document.sections.count
        }
        return total
    }

    public var blockCount: Int {
        var total = 0
        for document in documents {
            for section in document.sections {
                total += section.blocks.count
            }
        }
        return total
    }
}

public enum AIGenerationError: LocalizedError, Equatable, Sendable {
    case liveRequestsDisabled
    case missingCredential(AIProviderID)
    case privacyApprovalRequired(Int)
    case unsupportedProvider(AIProviderID)
    case inputTooLarge(maximumCharacters: Int)
    case budgetExceeded(spentUSD: Double, projectedUSD: Double, budgetUSD: Double)
    case provider(message: String, retryable: Bool)
    case emptyProviderResponse

    public var errorDescription: String? {
        switch self {
        case .liveRequestsDisabled:
            "Les appels payants sont désactivés dans les réglages."
        case let .missingCredential(provider):
            "Aucune clé API n’est enregistrée pour \(provider.displayName)."
        case let .privacyApprovalRequired(count):
            "L’envoi est bloqué par \(count) alerte(s) de confidentialité."
        case let .unsupportedProvider(provider):
            "Aucun adaptateur n’est disponible pour \(provider.displayName)."
        case let .inputTooLarge(maximum):
            "Le contenu dépasse la limite de \(maximum) caractères par essai."
        case let .budgetExceeded(spent, projected, budget):
            "Budget bloquant : \(Self.currency(spent + projected)) projetés pour un plafond de \(Self.currency(budget))."
        case let .provider(message, _):
            "Le fournisseur a refusé la requête : \(message)"
        case .emptyProviderResponse:
            "Le fournisseur n’a renvoyé aucun JSON exploitable."
        }
    }

    public var isRetryable: Bool {
        if case let .provider(_, retryable) = self { return retryable }
        return false
    }

    private static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}

public struct AIGenerationPolicy: Sendable {
    public var maximumInputCharacters: Int
    public var maximumRetries: Int

    public init(maximumInputCharacters: Int = 600_000, maximumRetries: Int = 2) {
        self.maximumInputCharacters = max(maximumInputCharacters, 10_000)
        self.maximumRetries = max(0, min(maximumRetries, 4))
    }
}

public enum AIModelCatalog {
    public static let profiles: [AIModelProfile] = {
        let verificationDate = Date(timeIntervalSince1970: 1_786_665_600) // 14 août 2026 UTC
        return [
            AIModelProfile(
                id: "openai-gpt-5.6-luna",
                provider: .openAI,
                modelID: "gpt-5.6-luna",
                displayName: "GPT-5.6 Luna — économique",
                inputPriceUSDPerMillionTokens: 0.20,
                outputPriceUSDPerMillionTokens: 1.20,
                pricingVerifiedAt: verificationDate,
                isLive: true
            ),
            AIModelProfile(
                id: "openai-gpt-5.6-terra",
                provider: .openAI,
                modelID: "gpt-5.6-terra",
                displayName: "GPT-5.6 Terra — équilibré",
                inputPriceUSDPerMillionTokens: 2,
                outputPriceUSDPerMillionTokens: 12,
                pricingVerifiedAt: verificationDate,
                isLive: true
            ),
            AIModelProfile(
                id: "openai-gpt-5.6-sol",
                provider: .openAI,
                modelID: "gpt-5.6-sol",
                displayName: "GPT-5.6 Sol — qualité maximale",
                inputPriceUSDPerMillionTokens: 5,
                outputPriceUSDPerMillionTokens: 30,
                pricingVerifiedAt: verificationDate,
                isLive: true
            )
        ]
    }()

    public static func profile(id: String) -> AIModelProfile? {
        profiles.first { $0.id == id }
    }
}

public actor StructuredGenerationOrchestrator {
    private let adapters: [AIProviderID: any AICloudGenerating]
    private let secretStore: any AISecretStoring
    private let runStore: any AIGenerationRunStoring
    private let validator: CourseGenerationValidator
    private let privacyGate: CloudPrivacyGate
    private let policy: AIGenerationPolicy
    private let transcriptService = TranscriptWorkspaceService()

    public init(
        adapters: [AIProviderID: any AICloudGenerating],
        secretStore: any AISecretStoring,
        runStore: any AIGenerationRunStoring,
        validator: CourseGenerationValidator = .init(),
        privacyGate: CloudPrivacyGate = .init(),
        policy: AIGenerationPolicy = .init()
    ) {
        self.adapters = adapters
        self.secretStore = secretStore
        self.runStore = runStore
        self.validator = validator
        self.privacyGate = privacyGate
        self.policy = policy
    }

    public func run(_ request: AIGenerationRequest) async throws -> AIGenerationRun {
        guard let adapter = adapters[request.modelProfile.provider] else {
            throw AIGenerationError.unsupportedProvider(request.modelProfile.provider)
        }
        if request.modelProfile.isLive && !request.preferences.liveRequestsEnabled {
            throw AIGenerationError.liveRequestsDisabled
        }

        let content = privacyContent(for: request)
        let fingerprint = transcriptService.stableFingerprint(content)
        switch privacyGate.evaluate(
            text: content,
            contentFingerprint: fingerprint,
            review: request.privacyReview
        ) {
        case .allowedNoIdentifiers, .allowedAfterManualReview:
            break
        case let .blocked(findings):
            throw AIGenerationError.privacyApprovalRequired(findings.count)
        }

        let input = providerInput(for: request)
        guard input.count <= policy.maximumInputCharacters else {
            throw AIGenerationError.inputTooLarge(maximumCharacters: policy.maximumInputCharacters)
        }
        let idempotencyKey = transcriptService.stableFingerprint(
            "scrib-generation-v1|\(request.course.id.rawValue.uuidString)|\(request.modelProfile.id)|\(fingerprint)"
        )
        if let cached = try await runStore.run(idempotencyKey: idempotencyKey) {
            return cached
        }

        let priorRuns = try await runStore.runs()
        let spent = priorRuns.map(\.usage.estimatedCostUSD).reduce(0, +)
        let estimatedInputTokens = max(input.utf8.count / 3, 1)
        let projected = request.modelProfile.estimatedCostUSD(
            inputTokens: estimatedInputTokens,
            outputTokens: request.preferences.maximumOutputTokens
        )
        if request.modelProfile.isLive,
           spent + projected > request.preferences.trialBudgetUSD {
            throw AIGenerationError.budgetExceeded(
                spentUSD: spent,
                projectedUSD: projected,
                budgetUSD: request.preferences.trialBudgetUSD
            )
        }

        let credential: String?
        if request.modelProfile.isLive {
            credential = try await secretStore.readSecret(for: request.modelProfile.provider)
            guard let credential, !credential.isEmpty else {
                throw AIGenerationError.missingCredential(request.modelProfile.provider)
            }
        } else {
            credential = nil
        }

        let providerRequest = AIProviderGenerationRequest(
            courseID: request.course.id,
            modelID: request.modelProfile.modelID,
            idempotencyKey: idempotencyKey,
            developerPrompt: developerPrompt,
            input: input,
            maximumOutputTokens: request.preferences.maximumOutputTokens
        )
        let startedAt = Date()
        let providerResponse = try await executeWithRetry {
            try await adapter.generate(providerRequest, credential: credential)
        }
        guard !providerResponse.payload.isEmpty else { throw AIGenerationError.emptyProviderResponse }
        let envelope = try validator.decodeAndValidate(
            providerResponse.payload,
            expectedCourseID: request.course.id
        )
        let completedAt = Date()
        let documents = try validator.makeDocuments(from: envelope, generatedAt: completedAt)
        let cost = request.modelProfile.estimatedCostUSD(
            inputTokens: providerResponse.usage.inputTokens,
            outputTokens: providerResponse.usage.outputTokens
        )
        let usage = AIGenerationUsageRecord(
            idempotencyKey: idempotencyKey,
            provider: request.modelProfile.provider,
            modelID: request.modelProfile.modelID,
            usage: providerResponse.usage,
            estimatedCostUSD: cost,
            createdAt: completedAt
        )
        let run = AIGenerationRun(
            courseID: request.course.id,
            idempotencyKey: idempotencyKey,
            modelProfile: request.modelProfile,
            envelope: envelope,
            documents: documents,
            usage: usage,
            completedAt: completedAt,
            durationMilliseconds: Int(completedAt.timeIntervalSince(startedAt) * 1_000)
        )
        try await runStore.save(run)
        return run
    }

    public func runs() async throws -> [AIGenerationRun] {
        try await runStore.runs().sorted { $0.completedAt > $1.completedAt }
    }

    private func executeWithRetry(
        _ operation: () async throws -> AIProviderGenerationResponse
    ) async throws -> AIProviderGenerationResponse {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch let error as AIGenerationError where error.isRetryable && attempt < policy.maximumRetries {
                attempt += 1
                let delay = UInt64(attempt * attempt) * 250_000_000
                let jitter = UInt64.random(in: 0...150_000_000)
                try await Task.sleep(nanoseconds: delay + jitter)
            }
        }
    }

    private func privacyContent(for request: AIGenerationRequest) -> String {
        request.transcript.plainText
            + "\n"
            + request.supportExtractions.map(\.plainText).joined(separator: "\n")
    }

    private func providerInput(for request: AIGenerationRequest) -> String {
        let supports = request.supportExtractions.map {
            "### Support : \($0.sourceFileName)\n\($0.plainText)"
        }.joined(separator: "\n\n")
        return """
        COURSE_ID: \(request.course.id.rawValue.uuidString)
        SEMESTRE: \(request.course.semester.displayName)
        UE: \(request.course.teachingUnit.displayName)
        TITRE: \(request.course.title)
        ENSEIGNANT: \(request.course.teacherName)

        ## Transcription horodatée
        \(request.transcript.plainText)

        ## Supports fournis par l’enseignant
        \(supports.isEmpty ? "Aucun support." : supports)
        """
    }

    private var developerPrompt: String {
        """
        Tu structures un cours infirmier en français à partir des seules données fournies.
        Produis exactement le contrat JSON Scrib 1.0 : un cours complet et une fiche de révision.
        N’invente aucune source, référence médicale, valeur, posologie ou identité.
        Conserve les incertitudes et informations médicales importantes avec leur horodatage audio.
        Les sources doivent rester vides tant qu’aucune source scientifique vérifiée n’est fournie.
        Ne renvoie aucun commentaire en dehors du JSON demandé.
        """
    }
}
