import AppKit
import Combine
import Foundation
import ScribApplication
import ScribDomain

@MainActor
final class RecordingViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case newCourse = "Nouveau cours"
        case segments = "Segments"
        case queue = "Suivi des cours"
        case settings = "Réglages"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .newCourse: "plus.circle"
            case .segments: "rectangle.split.2x1"
            case .queue: "clock.arrow.circlepath"
            case .settings: "gearshape"
            }
        }
    }

    @Published var selectedSection: Section? = .newCourse
    @Published var selectedSemester: Semester = .semester1 {
        didSet {
            guard selectedTeachingUnit.semester != selectedSemester else { return }
            selectedTeachingUnit = teachingUnits.first!
        }
    }
    @Published var selectedTeachingUnit: TeachingUnit = TeachingUnitCatalog.units(
        for: .semester1
    ).first!
    @Published var title = ""
    @Published var teacherName = ""
    @Published var expectedDuration: ExpectedDuration = .twoHours
    @Published private(set) var savedTeachers: [Teacher] = []
    @Published private(set) var snapshot = AudioRecorderSnapshot()
    @Published private(set) var currentCourse: Course?
    @Published private(set) var lastAvailableCapacity: Int64?
    @Published private(set) var lowSoundWarning = false
    @Published private(set) var processingJobs: [ProcessingJob] = []
    @Published var trackingFilter: CourseTrackingFilter = .all {
        didSet { selectFirstVisibleJobIfNeeded() }
    }
    @Published var selectedProcessingJobID: ProcessingJobID?
    @Published private(set) var systemConditions = SystemConditionSnapshot(
        isOnExternalPower: false,
        isNetworkAvailable: false,
        thermalCondition: .unknown
    )
    @Published var authorizationRequested = false
    @Published var errorMessage: String?
    @Published var quitWarningRequested = false

    private let recorder: any AudioRecording
    private let fileStore: any CourseFileStoring
    private let teacherStore: any TeacherAuthorizationStoring
    private let queueCoordinator: ProcessingQueueCoordinator
    private let readinessValidator = RecordingReadinessValidator()
    private let trackingPresenter = CourseTrackingPresenter()
    private var pendingTeacher: Teacher?
    private var pollingTask: Task<Void, Never>?
    private var queuePollingTask: Task<Void, Never>?
    private var lowSoundStartedAt: Date?
    private var systemActivity: NSObjectProtocol?

    init(
        recorder: any AudioRecording,
        fileStore: any CourseFileStoring,
        teacherStore: any TeacherAuthorizationStoring,
        queueCoordinator: ProcessingQueueCoordinator,
        startupWarning: String? = nil
    ) {
        self.recorder = recorder
        self.fileStore = fileStore
        self.teacherStore = teacherStore
        self.queueCoordinator = queueCoordinator
        self.savedTeachers = teacherStore.teachers()
        self.errorMessage = startupWarning
    }

    var teachingUnits: [TeachingUnit] {
        TeachingUnitCatalog.units(for: selectedSemester)
    }

    var isRecording: Bool { snapshot.state == .recording }
    var isPaused: Bool { snapshot.state == .paused }
    var hasActiveSession: Bool { isRecording || isPaused }

    var canStart: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !teacherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasActiveSession
    }

    var estimatedAudioSize: Int64 {
        AudioStoragePolicy.requiredBytes(for: expectedDuration)
    }

    var trackingSummary: CourseTrackingSummary {
        trackingPresenter.summary(for: processingJobs)
    }

    var filteredProcessingJobs: [ProcessingJob] {
        trackingPresenter.jobs(processingJobs, matching: trackingFilter)
    }

    var selectedProcessingJob: ProcessingJob? {
        guard let selectedProcessingJobID else { return filteredProcessingJobs.first }
        return processingJobs.first { $0.id == selectedProcessingJobID }
    }

    func trackingTimeline(for job: ProcessingJob) -> [CourseTrackingStageItem] {
        trackingPresenter.timeline(for: job)
    }

    var menuBarSystemImage: String {
        if isRecording { return "record.circle.fill" }
        if isPaused { return "pause.circle.fill" }
        return "waveform"
    }

    var menuBarStatus: String {
        if isRecording { return "Enregistrement — \(formattedElapsed)" }
        if isPaused { return "En pause — \(formattedElapsed)" }
        return "Scrib est prêt"
    }

    var formattedElapsed: String {
        let seconds = Int(snapshot.elapsed.rounded(.down))
        return String(
            format: "%02d:%02d:%02d",
            seconds / 3_600,
            (seconds % 3_600) / 60,
            seconds % 60
        )
    }

    func chooseTeacher(_ teacher: Teacher) {
        teacherName = teacher.name
    }

    func startTapped() {
        let trimmedName = teacherName.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacher = teacherStore.teacher(named: trimmedName) ?? Teacher(name: trimmedName)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !teacher.name.isEmpty else {
            errorMessage = "Le titre du cours et l’enseignant sont obligatoires."
            return
        }

        if !teacher.hasRecordingAuthorization {
            pendingTeacher = teacher
            authorizationRequested = true
            return
        }

        Task { await beginRecording(with: teacher) }
    }

    func prepareQueue() async {
        do {
            try await queueCoordinator.recoverInterruptedJobs()
            await reloadQueue()
            startQueuePolling()
        } catch {
            errorMessage = "La file d’attente n’a pas pu être restaurée : \(error.localizedDescription)"
        }
    }

    func reloadQueue() async {
        do {
            processingJobs = try await queueCoordinator.jobs()
            systemConditions = await queueCoordinator.currentConditions()
            selectFirstVisibleJobIfNeeded()
        } catch {
            errorMessage = "La file d’attente n’a pas pu être lue : \(error.localizedDescription)"
        }
    }

    func retry(_ job: ProcessingJob) {
        Task {
            do {
                try await queueCoordinator.retry(jobID: job.id)
                await reloadQueue()
            } catch {
                errorMessage = "Le cours n’a pas pu être relancé : \(error.localizedDescription)"
            }
        }
    }

    func selectProcessingJob(_ id: ProcessingJobID?) {
        selectedProcessingJobID = id
    }

    private func selectFirstVisibleJobIfNeeded() {
        let visible = filteredProcessingJobs
        guard !visible.isEmpty else {
            selectedProcessingJobID = nil
            return
        }
        if let selectedProcessingJobID, visible.contains(where: { $0.id == selectedProcessingJobID }) {
            return
        }
        selectedProcessingJobID = visible.first?.id
    }

    func confirmAuthorizationAndStart() {
        guard var teacher = pendingTeacher else { return }
        teacher.confirmRecordingAuthorization()
        do {
            try teacherStore.save(teacher)
            savedTeachers = teacherStore.teachers()
            pendingTeacher = nil
            authorizationRequested = false
            Task { await beginRecording(with: teacher) }
        } catch {
            errorMessage = "L’autorisation n’a pas pu être mémorisée : \(error.localizedDescription)"
        }
    }

    func cancelAuthorization() {
        pendingTeacher = nil
        authorizationRequested = false
    }

    func pause() {
        do {
            try recorder.pause()
            updateSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resume() {
        do {
            try recorder.resume()
            updateSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        do {
            _ = try recorder.stop()
            updateSnapshot()
            stopPolling()
            endSystemActivity()
            selectedSection = .segments
            let capturedCourse = currentCourse
            Task {
                await queueCoordinator.recordingDidStop()
                if let capturedCourse {
                    do {
                        _ = try await queueCoordinator.enqueue(course: capturedCourse)
                    } catch {
                        errorMessage = "Le cours n’a pas pu être ajouté à la file : \(error.localizedDescription)"
                    }
                }
                await reloadQueue()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentQuitWarning() {
        quitWarningRequested = true
    }

    func confirmQuitAndStop() {
        if hasActiveSession {
            stop()
        }
        NSApplication.shared.terminate(nil)
    }

    private func beginRecording(with teacher: Teacher) async {
        let course = Course(
            semester: selectedSemester,
            teachingUnit: selectedTeachingUnit,
            title: title,
            teacher: teacher,
            expectedDuration: expectedDuration
        )

        do {
            let directory = try fileStore.recordingDirectory(for: course)
            let available = try fileStore.availableCapacity(for: directory)
            lastAvailableCapacity = available
            try readinessValidator.validate(
                course: course,
                teacher: teacher,
                availableCapacity: available
            )

            guard await recorder.requestPermission() else {
                errorMessage = "L’accès au microphone est refusé. Autorisez Scrib dans Réglages Système > Confidentialité et sécurité > Microphone."
                return
            }

            await queueCoordinator.recordingDidStart()
            do {
                try recorder.start(courseID: course.id, directory: directory)
            } catch {
                await queueCoordinator.recordingDidStop()
                throw error
            }
            currentCourse = course
            updateSnapshot()
            beginSystemActivity()
            startPolling()
        } catch let issue as RecordingReadinessIssue {
            errorMessage = message(for: issue)
        } catch {
            errorMessage = "Impossible de démarrer l’enregistrement : \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateSnapshot()
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        lowSoundStartedAt = nil
        lowSoundWarning = false
    }

    private func startQueuePolling() {
        queuePollingTask?.cancel()
        queuePollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.reloadQueue()
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
            }
        }
    }

    private func updateSnapshot() {
        snapshot = recorder.snapshot()
        updateLowSoundWarning()
        if snapshot.state == .failed {
            stopPolling()
            endSystemActivity()
            Task { await queueCoordinator.recordingDidStop() }
            errorMessage = snapshot.incidentMessage ?? "L’enregistrement audio s’est interrompu."
        }
    }

    private func updateLowSoundWarning() {
        guard snapshot.state == .recording else {
            lowSoundStartedAt = nil
            lowSoundWarning = false
            return
        }

        if snapshot.averagePowerDecibels < -55 {
            lowSoundStartedAt = lowSoundStartedAt ?? Date()
            lowSoundWarning = Date().timeIntervalSince(lowSoundStartedAt!) >= 5
        } else {
            lowSoundStartedAt = nil
            lowSoundWarning = false
        }
    }

    private func beginSystemActivity() {
        guard systemActivity == nil else { return }
        systemActivity = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiated,
                .idleSystemSleepDisabled,
                .idleDisplaySleepDisabled,
                .suddenTerminationDisabled
            ],
            reason: "Enregistrement d’un cours dans Scrib"
        )
    }

    private func endSystemActivity() {
        guard let systemActivity else { return }
        ProcessInfo.processInfo.endActivity(systemActivity)
        self.systemActivity = nil
    }

    private func message(for issue: RecordingReadinessIssue) -> String {
        switch issue {
        case .incompleteCourse:
            "Les informations du cours sont incomplètes."
        case .teacherAuthorizationRequired:
            "L’autorisation d’enregistrer cet enseignant doit être confirmée."
        case let .insufficientStorage(required, available):
            "Espace insuffisant : \(formatBytes(available)) disponibles, \(formatBytes(required)) nécessaires."
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
