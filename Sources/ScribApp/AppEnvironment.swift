import ScribApplication
import ScribInfrastructure

@MainActor
struct AppEnvironment {
    let queueCoordinator: ProcessingQueueCoordinator
    let persistenceWarning: String?

    static func live() -> AppEnvironment {
        let repository: any ProcessingJobRepository
        let warning: String?
        do {
            repository = try SwiftDataProcessingJobRepository()
            warning = nil
        } catch {
            repository = InMemoryProcessingJobRepository()
            warning = "La base persistante n’a pas pu être ouverte. La file sera temporaire : \(error.localizedDescription)"
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
            persistenceWarning: warning
        )
    }
}
