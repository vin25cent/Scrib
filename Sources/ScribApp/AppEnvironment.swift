import ScribApplication
import ScribInfrastructure

@MainActor
struct AppEnvironment {
    let queueCoordinator: ProcessingQueueCoordinator
    let demonstrationPipeline: any DemonstrationPipelineRunning
    let supportImporter: any SupportDocumentImporting
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

        return AppEnvironment(
            queueCoordinator: coordinator,
            demonstrationPipeline: LocalDemonstrationPipeline(repository: repository),
            supportImporter: supportImporter,
            persistenceWarning: warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        )
    }
}
