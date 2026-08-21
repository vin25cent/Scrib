import AppKit
import ScribInfrastructure
import SwiftUI

@main
@MainActor
struct ScribDesktopApp: App {
    @NSApplicationDelegateAdaptor(ScribApplicationDelegate.self) private var applicationDelegate
    private let environment: AppEnvironment
    @StateObject private var model: RecordingViewModel

    init() {
        let environment = AppEnvironment.live()
        self.environment = environment
        let model = RecordingViewModel(
            recorder: environment.recordingSessionStore.map { AVFoundationAudioRecorder(sessionStore: $0) }
                ?? AVFoundationAudioRecorder(),
            fileStore: MacCourseFileStore(),
            teacherStore: UserDefaultsTeacherAuthorizationStore(),
            queueCoordinator: environment.queueCoordinator,
            supportImporter: environment.supportImporter,
            aiSecretStore: environment.aiSecretStore,
            aiPreferencesStore: environment.aiPreferencesStore,
            transcriptionCoordinator: environment.transcriptionCoordinator,
            recordingSessionStore: environment.recordingSessionStore,
            startupWarning: environment.persistenceWarning
        )
        _model = StateObject(
            wrappedValue: model
        )
        applicationDelegate.recordingModel = model
        Task {
            await MacProcessingNotificationSender().requestAuthorization()
        }
    }

    var body: some Scene {
        WindowGroup("Scrib") {
            ContentView(model: model)
                .frame(minWidth: 1_080, minHeight: 700)
        }

        MenuBarExtra("Scrib", systemImage: model.menuBarSystemImage) {
            Text(model.menuBarStatus)
            if model.isRecording {
                Button("Mettre en pause") { model.pause() }
                Button("Terminer") { model.stop() }
            } else if model.isPaused {
                Button("Reprendre") { model.resume() }
                Button("Terminer") { model.stop() }
            }
            Divider()
            Button("Quitter Scrib") {
                guard !model.hasActiveSession else {
                    model.presentQuitWarning()
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
