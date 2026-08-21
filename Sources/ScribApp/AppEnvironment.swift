import ScribApplication
import ScribInfrastructure

@MainActor
struct AppEnvironment {
    let processingTracker: ProcessingActivityTracker
    let supportImporter: any SupportDocumentImporting
    let aiSecretStore: any AISecretStoring
    let aiPreferencesStore: any AIGenerationPreferencesStoring
    let transcriptionCoordinator: LocalTranscriptionCoordinator
    let recordingSessionStore: (any RecordingSessionStoring)?
    let persistenceWarning: String?

    static func live() -> AppEnvironment {
        let repository: any ProcessingJobRepository
        var warnings: [String] = []
        do {
            repository = try SwiftDataProcessingJobRepository()
        } catch {
            repository = InMemoryProcessingJobRepository()
            warnings.append("La base persistante n’a pas pu être ouverte. Le suivi sera temporaire : \(error.localizedDescription)")
        }

        let supportImporter: any SupportDocumentImporting
        supportImporter = LocalSupportDocumentStore()

        let tracker = ProcessingActivityTracker(repository: repository)

        let aiSecretStore: any AISecretStoring = MacKeychainSecretStore()
        let aiPreferencesStore = UserDefaultsAIGenerationPreferencesStore()

        let recordingSessionStore: (any RecordingSessionStoring)?
        do {
            recordingSessionStore = try LocalRecordingSessionStore()
        } catch {
            recordingSessionStore = nil
            warnings.append("Les sessions audio ne peuvent pas être sécurisées : \(error.localizedDescription)")
        }

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
            processingTracker: tracker,
            supportImporter: supportImporter,
            aiSecretStore: aiSecretStore,
            aiPreferencesStore: aiPreferencesStore,
            transcriptionCoordinator: transcriptionCoordinator,
            recordingSessionStore: recordingSessionStore,
            persistenceWarning: warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        )
    }
}
