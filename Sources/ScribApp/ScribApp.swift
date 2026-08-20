import AppKit
import ScribInfrastructure
import SwiftUI

@main
@MainActor
struct ScribDesktopApp: App {
    private let environment: AppEnvironment
    @StateObject private var model: RecordingViewModel

    init() {
        let environment = AppEnvironment.live()
        self.environment = environment
        _model = StateObject(
            wrappedValue: RecordingViewModel(
                recorder: AVFoundationAudioRecorder(),
                fileStore: MacCourseFileStore(),
                teacherStore: UserDefaultsTeacherAuthorizationStore(),
                queueCoordinator: environment.queueCoordinator,
                supportImporter: environment.supportImporter,
                aiSecretStore: environment.aiSecretStore,
                aiPreferencesStore: environment.aiPreferencesStore,
                transcriptionCoordinator: environment.transcriptionCoordinator,
                startupWarning: environment.persistenceWarning
            )
        )
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
                guard !model.isRecording && !model.isPaused else {
                    model.presentQuitWarning()
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
