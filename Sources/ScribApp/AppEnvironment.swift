import ScribApplication
import ScribInfrastructure

@MainActor
struct AppEnvironment {
    let queueCoordinator: ProcessingQueueCoordinator
    let supportImporter: any SupportDocumentImporting
    let aiSecretStore: any AISecretStoring
    let aiPreferencesStore: any AIGenerationPreferencesStoring
    let transcriptionCoordinator: LocalTranscriptionCoordinator
    let persistenceWarning: String?

    static func live() -> AppEnvironment {
        let repository: any ProcessingJobRepository
        var warnings: [String] = []
        do {
            repository = try SwiftDataProcessingJobRepository()
        } catch {
            repository = InMemoryProcessingJobRepository()
            warnings.append("La base persistante n’a pas pu être ouverte. La file sera temporaire : \(error.localizedDescription)")
        }

        let supportImporter: any SupportDocumentImporting
        do {
            supportImporter = try LocalSupportDocumentStore()
        } catch {
            supportImporter = InMemorySupportDocumentStore()
            warnings.append("Les supports importés ne seront pas conservés après fermeture : \(error.localizedDescription)")
        }

        let monitor = MacSystemConditionMonitor()
        let notifications = MacProcessingNotificationSender()
        let coordinator = ProcessingQueueCoordinator(
            repository: repository,
            conditions: monitor,
            executor: DeferredPipelineExecutor(),
            notifications: notifications
        )

        let aiSecretStore: any AISecretStoring = MacKeychainSecretStore()
        let aiPreferencesStore = UserDefaultsAIGenerationPreferencesStore()

        let transcriptionCoordinator: LocalTranscriptionCoordinator
        do {
            let modelManager = try WhisperKitModelManager()
            let transcriptionStore = try LocalTranscriptionStore()
            transcriptionCoordinator = LocalTranscriptionCoordinator(
                engine: WhisperKitTranscriptionEngine(modelManager: modelManager),
                modelManager: modelManager,
                store: transcriptionStore
            )
        } catch {
            let message = "La transcription locale ne peut pas initialiser son stockage : \(error.localizedDescription)"
            let unavailableManager = UnavailableTranscriptionModelManager(message: message)
            transcriptionCoordinator = LocalTranscriptionCoordinator(
                engine: UnavailableTranscriptionEngine(message: message),
                modelManager: unavailableManager,
                store: InMemoryLocalTranscriptionStore()
            )
            warnings.append(message)
        }

        return AppEnvironment(
            queueCoordinator: coordinator,
            supportImporter: supportImporter,
            aiSecretStore: aiSecretStore,
            aiPreferencesStore: aiPreferencesStore,
            transcriptionCoordinator: transcriptionCoordinator,
            persistenceWarning: warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        )
    }
}
