import AppKit

@MainActor
final class ScribApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var recordingModel: RecordingViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let recordingModel, recordingModel.hasActiveSession else {
            return .terminateNow
        }
        do {
            try recordingModel.finalizeForTermination()
            return .terminateNow
        } catch {
            recordingModel.errorMessage = "La fermeture est annulée : l'enregistrement n'a pas pu être finalisé et sécurisé. \(error.localizedDescription)"
            return .terminateCancel
        }
    }
}
