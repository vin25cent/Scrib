#if os(macOS)
import ScribApplication
import ScribDomain
import UserNotifications

public struct MacProcessingNotificationSender: ProcessingNotificationSending {
    public init() {}

    public func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        )
    }

    public func processingDidComplete(job: ProcessingJob) async {
        await send(
            title: "Cours prêt",
            body: "\(job.teachingUnit) — \(job.courseTitle) est terminé.",
            identifier: "scrib-completed-\(job.id.rawValue.uuidString)"
        )
    }

    public func processingNeedsAttention(job: ProcessingJob) async {
        await send(
            title: "Scrib nécessite votre attention",
            body: job.lastError ?? "Le traitement de \(job.courseTitle) doit être relancé.",
            identifier: "scrib-attention-\(job.id.rawValue.uuidString)"
        )
    }

    private func send(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
#endif
