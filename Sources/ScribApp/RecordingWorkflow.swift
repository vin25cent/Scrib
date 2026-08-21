import Combine
import Foundation
import ScribApplication
import ScribDomain

/// Owns one recording session from course form to finalized audio segments.
///
/// `snapshot.segments` is the recorder's live view (including pauses and incidents).
/// `capturedSegments` is deliberately separate: it is the stable, sorted result returned
/// by `stop()` and is the only representation passed to transcription and export.
@MainActor
final class RecordingWorkflow: ObservableObject {
    @Published var selectedSemester: Semester = .semester1 {
        didSet {
            guard selectedTeachingUnit.semester != selectedSemester else { return }
            selectedTeachingUnit = teachingUnits.first!
        }
    }
    @Published var selectedTeachingUnit = TeachingUnitCatalog.units(for: .semester1).first!
    @Published var title = ""
    @Published var teacherName = ""
    @Published var expectedDuration: ExpectedDuration = .twoHours
    @Published private(set) var savedTeachers: [Teacher]
    @Published private(set) var snapshot = AudioRecorderSnapshot()
    @Published private(set) var currentCourse: Course?
    @Published private(set) var capturedSegments: [RecordingSegment] = []
    @Published private(set) var existingAudioIssues: [RecordingSessionRecoveryIssue] = []
    @Published private(set) var lastAvailableCapacity: Int64?
    @Published private(set) var lowSoundWarning = false
    @Published private(set) var processingJobs: [ProcessingJob] = []
    @Published var trackingFilter: CourseTrackingFilter = .all {
        didSet { selectFirstVisibleJobIfNeeded() }
    }
    @Published var selectedProcessingJobID: ProcessingJobID?
    @Published var authorizationRequested = false
    @Published private(set) var recordingWorkflowState: RecordingWorkflowState = .idle

    var reportError: @MainActor (String) -> Void = { _ in }
    var reportNotice: @MainActor (String) -> Void = { _ in }
    var didBeginNewRecording: @MainActor () -> Void = {}
    var didFinishRecording: @MainActor () -> Void = {}
    var didRecoverRecording: @MainActor () -> Void = {}

    private let recorder: any AudioRecording
    private let fileStore: any CourseFileStoring
    private let teacherStore: any TeacherAuthorizationStoring
    private let processingTracker: ProcessingActivityTracker
    private let recordingSessionStore: (any RecordingSessionStoring)?
    private let readinessValidator = RecordingReadinessValidator()
    private let trackingPresenter = CourseTrackingPresenter()
    private var pendingTeacher: Teacher?
    private var pollingTask: Task<Void, Never>?
    private var recordingStartTask: Task<Void, Never>?
    private var recordingStartTaskID: UUID?
    private var recordingCompletionTask: Task<Void, Never>?
    private var recordingCompletionID: UUID?
    private var lowSoundStartedAt: Date?
    private var systemActivity: NSObjectProtocol?
    private var recordingStartGate = RecordingStartGate()

    init(
        recorder: any AudioRecording,
        fileStore: any CourseFileStoring,
        teacherStore: any TeacherAuthorizationStoring,
        processingTracker: ProcessingActivityTracker,
        recordingSessionStore: (any RecordingSessionStoring)?
    ) {
        self.recorder = recorder
        self.fileStore = fileStore
        self.teacherStore = teacherStore
        self.processingTracker = processingTracker
        self.recordingSessionStore = recordingSessionStore
        self.savedTeachers = teacherStore.teachers()
    }

    var teachingUnits: [TeachingUnit] { TeachingUnitCatalog.units(for: selectedSemester) }
    var isRecording: Bool { snapshot.state == .recording }
    var isPaused: Bool { snapshot.state == .paused }
    var isStartingRecording: Bool { recordingWorkflowState == .starting }
    var isStoppingRecording: Bool { recordingWorkflowState == .stopping }
    var hasActiveSession: Bool {
        isRecording || isPaused || isStartingRecording || isStoppingRecording
    }
    var canStart: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !teacherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasActiveSession
    }
    var estimatedAudioSize: Int64 { AudioStoragePolicy.requiredBytes(for: expectedDuration) }
    var trackingSummary: CourseTrackingSummary { trackingPresenter.summary(for: processingJobs) }
    var filteredProcessingJobs: [ProcessingJob] {
        trackingPresenter.jobs(processingJobs, matching: trackingFilter)
    }
    var selectedProcessingJob: ProcessingJob? {
        guard let selectedProcessingJobID else { return filteredProcessingJobs.first }
        return processingJobs.first { $0.id == selectedProcessingJobID }
    }

    func chooseTeacher(_ teacher: Teacher) { teacherName = teacher.name }

    func prepareProcessingTracking() async {
        do {
            try await processingTracker.recoverInterruptedActivities()
            await reloadProcessingTracking()
        } catch {
            reportError(
                "Le suivi des activités n’a pas pu être restauré : \(error.localizedDescription)")
        }
    }

    func reloadProcessingTracking() async {
        do {
            processingJobs = try await processingTracker.jobs()
            selectFirstVisibleJobIfNeeded()
        } catch {
            reportError("Le suivi des activités n’a pas pu être lu : \(error.localizedDescription)")
        }
    }

    func selectProcessingJob(_ id: ProcessingJobID?) { selectedProcessingJobID = id }

    func startTapped() {
        let trimmedName = teacherName.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacher = teacherStore.teacher(named: trimmedName) ?? Teacher(name: trimmedName)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !teacher.name.isEmpty
        else {
            reportError("Le titre du cours et l’enseignant sont obligatoires.")
            return
        }
        if !teacher.hasRecordingAuthorization {
            pendingTeacher = teacher
            authorizationRequested = true
            return
        }
        launchRecordingStart(with: teacher)
    }

    func confirmAuthorizationAndStart() {
        guard var teacher = pendingTeacher else { return }
        teacher.confirmRecordingAuthorization()
        do {
            try teacherStore.save(teacher)
            savedTeachers = teacherStore.teachers()
            pendingTeacher = nil
            authorizationRequested = false
            launchRecordingStart(with: teacher)
        } catch {
            reportError("L’autorisation n’a pas pu être mémorisée : \(error.localizedDescription)")
        }
    }

    func cancelAuthorization() {
        pendingTeacher = nil
        authorizationRequested = false
    }

    func pause() {
        guard recordingWorkflowState == .recording else { return }
        do {
            try recorder.pause()
            _ = recordingStartGate.pause()
            syncRecordingWorkflowState()
            updateSnapshot()
            updateTrackingAfterPause(true)
        } catch { reportError(error.localizedDescription) }
    }

    func resume() {
        guard recordingWorkflowState == .paused else { return }
        do {
            try recorder.resume()
            _ = recordingStartGate.resume()
            syncRecordingWorkflowState()
            updateSnapshot()
            updateTrackingAfterPause(false)
        } catch { reportError(error.localizedDescription) }
    }

    func stop() {
        if recordingWorkflowState == .starting {
            cancelRecordingStart()
            reportNotice("Démarrage de l'enregistrement annulé.")
            return
        }
        guard recordingWorkflowState == .recording || recordingWorkflowState == .paused else {
            return
        }
        do {
            let course = try finalizeRecording()
            didRecoverRecording()
            scheduleRecordingCompletion(for: course)
        } catch { reportError(error.localizedDescription) }
    }

    func finalizeForTermination() throws {
        if recordingWorkflowState == .starting {
            cancelRecordingStart()
            return
        }
        guard recordingWorkflowState == .recording || recordingWorkflowState == .paused else {
            return
        }
        _ = try finalizeRecording()
    }

    func restoreRecoverableRecordingSession() {
        do {
            guard let recovered = try recordingSessionStore?.recoverableSessions().first else {
                return
            }
            currentCourse = recovered.manifest.course
            capturedSegments = recovered.recordingSegments
            existingAudioIssues = recovered.issues
            snapshot = AudioRecorderSnapshot(
                state: .finished, elapsed: capturedSegments.reduce(0) { $0 + $1.duration },
                segments: capturedSegments,
                incidentMessage: recovered.issues.isEmpty
                    ? nil : "Des éléments de cette session nécessitent une vérification.")
            let details = recovered.issues.map(\.localizedDescription).joined(separator: " ")
            reportNotice(
                recovered.issues.isEmpty
                    ? "Une session audio non transcrite a été restaurée pour \(recovered.manifest.course.title)."
                    : "Session audio restaurée avec précaution. \(details)")
            didFinishRecording()
        } catch {
            reportError(
                "Une session audio n'a pas pu être restaurée : \(error.localizedDescription)")
        }
    }

    func restoreTranscriptionAudio(_ stored: StoredLocalTranscription) {
        currentCourse = stored.course
        do {
            if let recovered = try recordingSessionStore?.recordingSession(for: stored.course.id) {
                capturedSegments = recovered.recordingSegments
                existingAudioIssues = recovered.issues
            } else {
                capturedSegments = stored.recordingSegments.sorted { $0.sequence < $1.sequence }
                existingAudioIssues = capturedSegments.compactMap { segment in
                    FileManager.default.fileExists(atPath: segment.fileURL.path)
                        ? nil
                        : .missingAudioFile(relativePath: segment.fileURL.lastPathComponent)
                }
            }
        } catch {
            capturedSegments = stored.recordingSegments.sorted { $0.sequence < $1.sequence }
            existingAudioIssues = []
            reportError("Les anciens enregistrements n’ont pas pu être vérifiés : \(error.localizedDescription)")
        }
        snapshot = AudioRecorderSnapshot(
            state: .finished, elapsed: capturedSegments.reduce(0) { $0 + $1.duration },
            segments: capturedSegments,
            incidentMessage: existingAudioIssues.first?.localizedDescription)
    }

    private func launchRecordingStart(with teacher: Teacher) {
        guard let startID = recordingStartGate.beginStart() else { return }
        syncRecordingWorkflowState()
        recordingStartTaskID = startID
        recordingStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if recordingStartTaskID == startID {
                    recordingStartTask = nil
                    recordingStartTaskID = nil
                }
            }
            await beginRecording(with: teacher, startID: startID)
        }
    }

    private func cancelRecordingStart() {
        guard recordingStartGate.cancelStart() != nil else { return }
        recordingStartTask?.cancel()
        recordingStartTask = nil
        recordingStartTaskID = nil
        syncRecordingWorkflowState()
    }

    private func beginRecording(with teacher: Teacher, startID: UUID) async {
        defer {
            if recordingStartGate.startID == startID {
                _ = recordingStartGate.recordingStartDidFail(id: startID)
                syncRecordingWorkflowState()
            }
        }
        guard recordingSessionStore != nil else {
            reportError(
                "L'enregistrement est indisponible : Scrib ne peut pas sécuriser le manifeste de session audio."
            )
            return
        }
        let course = Course(
            semester: selectedSemester, teachingUnit: selectedTeachingUnit, title: title,
            teacher: teacher, expectedDuration: expectedDuration)
        do {
            try Task.checkCancellation()
            guard recordingStartGate.startID == startID else { throw CancellationError() }
            let directory = try fileStore.recordingDirectory(for: course)
            let available = try fileStore.availableCapacity(for: directory)
            lastAvailableCapacity = available
            try readinessValidator.validate(
                course: course, teacher: teacher, availableCapacity: available)
            guard await recorder.requestPermission() else {
                reportError(
                    "L’accès au microphone est refusé. Autorisez Scrib dans Réglages Système > Confidentialité et sécurité > Microphone."
                )
                return
            }
            try Task.checkCancellation()
            guard recordingStartGate.startID == startID else { throw CancellationError() }
            if let recordingCompletionTask { await recordingCompletionTask.value }
            try Task.checkCancellation()
            guard recordingStartGate.startID == startID else { throw CancellationError() }
            try recorder.start(course: course, directory: directory)
            guard recordingStartGate.recordingDidStart(id: startID) else {
                _ = try? recorder.stop()
                return
            }
            syncRecordingWorkflowState()
            currentCourse = course
            capturedSegments = []
            existingAudioIssues = []
            didBeginNewRecording()
            do {
                _ = try await processingTracker.start(course: course, activity: .recording)
                try await processingTracker.markRunning(courseID: course.id, activity: .recording)
                await reloadProcessingTracking()
            } catch {
                reportError(
                    "L’enregistrement continue, mais son suivi n’a pas pu être mis à jour : \(error.localizedDescription)"
                )
            }
            updateSnapshot()
            beginSystemActivity()
            startPolling()
        } catch is CancellationError {
            if recordingStartGate.startID == startID {
                _ = recordingStartGate.cancelStart()
                syncRecordingWorkflowState()
            }
        } catch let issue as RecordingReadinessIssue {
            reportError(message(for: issue))
        } catch {
            reportError("Impossible de démarrer l’enregistrement : \(error.localizedDescription)")
        }
    }

    private func finalizeRecording() throws -> Course? {
        guard recordingStartGate.beginStop() else { return nil }
        syncRecordingWorkflowState()
        do {
            capturedSegments = try recorder.stop().sorted { $0.sequence < $1.sequence }
            updateSnapshot()
            stopPolling()
            endSystemActivity()
            recordingStartGate.stopDidFinish()
            syncRecordingWorkflowState()
            return currentCourse
        } catch {
            recordingStartGate.stopDidFail()
            syncRecordingWorkflowState()
            throw error
        }
    }

    private func scheduleRecordingCompletion(for course: Course?) {
        let id = UUID()
        recordingCompletionID = id
        recordingCompletionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if recordingCompletionID == id {
                    recordingCompletionTask = nil
                    recordingCompletionID = nil
                }
            }
            if let course {
                do {
                    try await processingTracker.complete(courseID: course.id, activity: .recording)
                } catch {
                    reportError(
                        "L’enregistrement est terminé, mais son suivi n’a pas pu être mis à jour : \(error.localizedDescription)"
                    )
                }
            }
            await reloadProcessingTracking()
        }
    }

    private func updateTrackingAfterPause(_ paused: Bool) {
        guard let course = currentCourse else { return }
        let tracker = processingTracker
        let at = Date()
        Task { [weak self] in
            if paused {
                try? await tracker.suspend(
                    courseID: course.id, activity: .recording,
                    reason: "Enregistrement mis en pause.", at: at)
            } else {
                try? await tracker.markRunning(courseID: course.id, activity: .recording, at: at)
            }
            await self?.reloadProcessingTracking()
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateSnapshot()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        lowSoundStartedAt = nil
        lowSoundWarning = false
    }
    private func updateSnapshot() {
        snapshot = recorder.snapshot()
        updateLowSoundWarning()
        guard snapshot.state == .failed else { return }
        stopPolling()
        endSystemActivity()
        recordingStartGate.stopDidFail()
        syncRecordingWorkflowState()
        scheduleRecordingCompletion(for: nil)
        let message = snapshot.incidentMessage ?? "L’enregistrement audio s’est interrompu."
        reportError(message)
        if let course = currentCourse {
            let tracker = processingTracker
            Task { [weak self] in
                try? await tracker.fail(courseID: course.id, activity: .recording, error: message)
                await self?.reloadProcessingTracking()
            }
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
                .userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled,
                .suddenTerminationDisabled,
            ], reason: "Enregistrement d’un cours dans Scrib")
    }
    private func endSystemActivity() {
        guard let systemActivity else { return }
        ProcessInfo.processInfo.endActivity(systemActivity)
        self.systemActivity = nil
    }
    private func syncRecordingWorkflowState() { recordingWorkflowState = recordingStartGate.state }
    private func selectFirstVisibleJobIfNeeded() {
        let visible = filteredProcessingJobs
        guard !visible.isEmpty else {
            selectedProcessingJobID = nil
            return
        }
        if let selectedProcessingJobID,
            visible.contains(where: { $0.id == selectedProcessingJobID })
        {
            return
        }
        selectedProcessingJobID = visible.first?.id
    }
    private func message(for issue: RecordingReadinessIssue) -> String {
        switch issue {
        case .incompleteCourse: "Les informations du cours sont incomplètes."
        case .teacherAuthorizationRequired:
            "L’autorisation d’enregistrer cet enseignant doit être confirmée."
        case .insufficientStorage(let required, let available):
            "Espace insuffisant : \(formatBytes(available)) disponibles, \(formatBytes(required)) nécessaires."
        }
    }
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
