import Foundation

public enum AIProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case simulated
    case openAI

    public var displayName: String {
        switch self {
        case .simulated: "Simulation locale"
        case .openAI: "OpenAI"
        }
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
        selectedModelProfileID: String = "scrib-simulated-v1",
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
    public var isSimulated: Bool

    public init(
        id: UUID = UUID(),
        idempotencyKey: String,
        provider: AIProviderID,
        modelID: String,
        usage: AIProviderUsage,
        estimatedCostUSD: Double,
        createdAt: Date = Date(),
        isSimulated: Bool
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
        self.isSimulated = isSimulated
    }
}
