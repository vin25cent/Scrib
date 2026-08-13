import AppKit
import ScribInfrastructure
import SwiftUI

@main
@MainActor
struct ScribDesktopApp: App {
    @StateObject private var model = RecordingViewModel(
        recorder: AVFoundationAudioRecorder(),
        fileStore: MacCourseFileStore(),
        teacherStore: UserDefaultsTeacherAuthorizationStore()
    )

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
