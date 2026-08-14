import Foundation
import ScribApplication
import ScribDomain

public actor InMemoryAISecretStore: AISecretStoring {
    private var secrets: [AIProviderID: String] = [:]

    public init() {}

    public func hasSecret(for provider: AIProviderID) -> Bool { secrets[provider] != nil }
    public func readSecret(for provider: AIProviderID) -> String? { secrets[provider] }

    public func saveSecret(_ secret: String, for provider: AIProviderID) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "Scrib.AISecret",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "La clé API est vide."]
            )
        }
        secrets[provider] = trimmed
    }

    public func deleteSecret(for provider: AIProviderID) { secrets[provider] = nil }
}

public actor InMemoryAIGenerationRunStore: AIGenerationRunStoring {
    private var storedRuns: [AIGenerationRun]

    public init(runs: [AIGenerationRun] = []) { self.storedRuns = runs }

    public func runs() -> [AIGenerationRun] { storedRuns }
    public func run(idempotencyKey: String) -> AIGenerationRun? {
        storedRuns.first { $0.idempotencyKey == idempotencyKey }
    }
    public func save(_ run: AIGenerationRun) {
        storedRuns.removeAll { $0.idempotencyKey == run.idempotencyKey }
        storedRuns.append(run)
    }
}

public actor LocalAIGenerationRunStore: AIGenerationRunStoring {
    private let manifestURL: URL
    private let fileManager: FileManager
    private var storedRuns: [AIGenerationRun]

    public init(rootDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        let root = try rootDirectory ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Scrib/AI", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        self.manifestURL = root.appendingPathComponent("generation-runs.json")
        self.fileManager = fileManager
        if fileManager.fileExists(atPath: manifestURL.path) {
            self.storedRuns = try JSONDecoder().decode(
                [AIGenerationRun].self,
                from: Data(contentsOf: manifestURL)
            )
        } else {
            self.storedRuns = []
        }
    }

    public func runs() -> [AIGenerationRun] { storedRuns }

    public func run(idempotencyKey: String) -> AIGenerationRun? {
        storedRuns.first { $0.idempotencyKey == idempotencyKey }
    }

    public func save(_ run: AIGenerationRun) throws {
        storedRuns.removeAll { $0.idempotencyKey == run.idempotencyKey }
        storedRuns.append(run)
        storedRuns = Array(storedRuns.sorted { $0.completedAt > $1.completedAt }.prefix(100))
        let data = try JSONEncoder().encode(storedRuns)
        try data.write(to: manifestURL, options: .atomic)
    }
}

@MainActor
public final class UserDefaultsAIGenerationPreferencesStore: AIGenerationPreferencesStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "scrib.ai-preferences.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AIGenerationPreferences {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(AIGenerationPreferences.self, from: data) else {
            return AIGenerationPreferences()
        }
        return value
    }

    public func save(_ preferences: AIGenerationPreferences) throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}

@MainActor
public final class InMemoryAIGenerationPreferencesStore: AIGenerationPreferencesStoring {
    private var preferences: AIGenerationPreferences
    public init(preferences: AIGenerationPreferences = .init()) { self.preferences = preferences }
    public func load() -> AIGenerationPreferences { preferences }
    public func save(_ preferences: AIGenerationPreferences) { self.preferences = preferences }
}
