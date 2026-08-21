import AppKit
import Combine
import Foundation
import ScribApplication
import ScribDomain
import SwiftUI
import UniformTypeIdentifiers

/// UI composition root; recording and transcription own their operational state.
@MainActor final class RecordingViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case newCourse = "Nouveau cours"
        case segments = "Segments"
        case localTranscription = "Transcription locale"
        case queue = "Suivi des cours"
        case transcript = "Transcription"
        case supports = "Documents enseignant"
        case privacy = "Confidentialité"
        case settings = "Réglages"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .newCourse: "plus.circle"
            case .segments: "rectangle.split.2x1"
            case .localTranscription: "waveform.badge.magnifyingglass"
            case .queue: "clock.arrow.circlepath"
            case .transcript: "text.alignleft"
            case .supports: "doc.badge.plus"
            case .privacy: "hand.raised.fill"
            case .settings: "gearshape"
            }
        }
    }
    @Published var selectedSection: Section? = .newCourse
    @Published var workspaceNotice: String?
    @Published var errorMessage: String?
    @Published var quitWarningRequested = false
    @Published private(set) var activeCourseSelection = ActiveCourseSelection()
    @Published private(set) var isLoadingActiveCourse = false
    @Published private(set) var supportDocuments: [SupportDocument] = []
    @Published private(set) var isImportingSupportDocument = false
    @Published private(set) var isDeletingSupportDocument = false
    @Published private(set) var privacyReview: PrivacyReview?
    @Published private(set) var aiPreferences: AIGenerationPreferences
    @Published var aiAPIKeyDraft = ""
    @Published private(set) var aiHasStoredKey = false
    let recording: RecordingWorkflow
    let transcription: LocalTranscriptionWorkflow
    private let supportImporter: any SupportDocumentImporting
    private let aiSecretStore: any AISecretStoring
    private let aiPreferencesStore: any AIGenerationPreferencesStoring
    private let transcriptService = TranscriptWorkspaceService()
    private let privacyDetector = PatientIdentifierDetector()
    private let privacyGate = CloudPrivacyGate()
    private var aiKeyStatusTask: Task<Void, Never>?
    private var aiKeyStatusGeneration = LatestOperationGeneration()
    private var activeCourseLoadGeneration = LatestOperationGeneration()
    private var activeCourseLoadTask: Task<Void, Never>?
    private var workflowObservers = Set<AnyCancellable>()

    init(
        recording: RecordingWorkflow, transcription: LocalTranscriptionWorkflow,
        supportImporter: any SupportDocumentImporting, aiSecretStore: any AISecretStoring,
        aiPreferencesStore: any AIGenerationPreferencesStoring, startupWarning: String? = nil
    ) {
        self.recording = recording
        self.transcription = transcription
        self.supportImporter = supportImporter
        self.aiSecretStore = aiSecretStore
        self.aiPreferencesStore = aiPreferencesStore
        var preferences = aiPreferencesStore.load()
        if AIModelCatalog.profile(id: preferences.selectedModelProfileID) == nil {
            preferences.selectedModelProfileID = AIModelCatalog.profiles[0].id
        }
        aiPreferences = preferences
        errorMessage = startupWarning
        bindWorkflows()
        startup()
    }
    private func bindWorkflows() {
        recording.reportError = { [weak self] in self?.errorMessage = $0 }
        recording.reportNotice = { [weak self] in self?.workspaceNotice = $0 }
        recording.didBeginNewRecording = { [weak self] in
            guard let self else { return }
            cancelActiveCourseLoad()
            if let course = self.recording.currentCourse { activeCourseSelection.select(course) }
            transcription.resetForNewRecording()
        }
        recording.didFinishRecording = { [weak self] in
            guard let self else { return }
            if let course = self.recording.currentCourse { activeCourseSelection.select(course) }
            selectedSection = .localTranscription
        }
        recording.didRecoverRecording = { [weak self] in
            guard let self else { return }
            if let course = self.recording.currentCourse { activeCourseSelection.select(course) }
            selectedSection = .segments
        }
        transcription.reportError = { [weak self] in self?.errorMessage = $0 }
        transcription.reportNotice = { [weak self] in self?.workspaceNotice = $0 }
        transcription.trackingDidChange = { [weak self] in
            await self?.reloadProcessingTracking()
        }
        recording.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(
            in: &workflowObservers)
        transcription.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(
                in: &workflowObservers)
    }
    private func startup() {
        Task { [weak self] in
            guard let self else { return }
            await refreshAIKeyStatus()
            await refreshSupportDocuments()
            await transcription.refreshModelStatus()
            if let stored = await transcription.restoreLatest() {
                activeCourseSelection.select(stored.course)
                recording.restoreTranscriptionAudio(stored)
            }
            recording.restoreRecoverableRecordingSession()
        }
    }

    // The facade keeps the existing SwiftUI views stable while reducing this type's state ownership.
    var selectedSemester: Semester {
        get { recording.selectedSemester }
        set { recording.selectedSemester = newValue }
    }
    var selectedTeachingUnit: TeachingUnit {
        get { recording.selectedTeachingUnit }
        set { recording.selectedTeachingUnit = newValue }
    }
    var title: String {
        get { recording.title }
        set { recording.title = newValue }
    }
    var teacherName: String {
        get { recording.teacherName }
        set { recording.teacherName = newValue }
    }
    var expectedDuration: ExpectedDuration {
        get { recording.expectedDuration }
        set { recording.expectedDuration = newValue }
    }
    var savedTeachers: [Teacher] { recording.savedTeachers }
    var snapshot: AudioRecorderSnapshot { recording.snapshot }
    var activeCourseID: CourseID? { activeCourseSelection.courseID }
    var activeCourseCameFromTracking: Bool { activeCourseSelection.trackingJobID != nil }
    var currentCourse: Course? {
        guard recording.currentCourse?.id == activeCourseID else { return nil }
        return recording.currentCourse
    }
    var capturedSegments: [RecordingSegment] {
        recording.currentCourse?.id == activeCourseID ? recording.capturedSegments : []
    }
    var existingAudioIssues: [RecordingSessionRecoveryIssue] {
        recording.currentCourse?.id == activeCourseID ? recording.existingAudioIssues : []
    }
    var lastAvailableCapacity: Int64? { recording.lastAvailableCapacity }
    var lowSoundWarning: Bool { recording.lowSoundWarning }
    var processingJobs: [ProcessingJob] { recording.processingJobs }
    var trackingFilter: CourseTrackingFilter {
        get { recording.trackingFilter }
        set {
            recording.trackingFilter = newValue
            if let job = recording.selectedProcessingJob {
                activateTrackedCourse(job, navigateToTranscription: false)
            }
        }
    }
    var selectedProcessingJobID: ProcessingJobID? {
        get { recording.selectedProcessingJobID }
        set { selectProcessingJob(newValue) }
    }
    var authorizationRequested: Bool {
        get { recording.authorizationRequested }
        set { recording.authorizationRequested = newValue }
    }
    var recordingWorkflowState: RecordingWorkflowState { recording.recordingWorkflowState }
    var teachingUnits: [TeachingUnit] { recording.teachingUnits }
    var isRecording: Bool { recording.isRecording }
    var isPaused: Bool { recording.isPaused }
    var isStartingRecording: Bool { recording.isStartingRecording }
    var isStoppingRecording: Bool { recording.isStoppingRecording }
    var hasActiveSession: Bool { recording.hasActiveSession }
    var canStart: Bool { recording.canStart }
    var estimatedAudioSize: Int64 { recording.estimatedAudioSize }
    var trackingSummary: CourseTrackingSummary { recording.trackingSummary }
    var filteredProcessingJobs: [ProcessingJob] { recording.filteredProcessingJobs }
    var selectedProcessingJob: ProcessingJob? { recording.selectedProcessingJob }
    func chooseTeacher(_ teacher: Teacher) { recording.chooseTeacher(teacher) }
    func startTapped() { recording.startTapped() }
    func confirmAuthorizationAndStart() { recording.confirmAuthorizationAndStart() }
    func cancelAuthorization() { recording.cancelAuthorization() }
    func pause() { recording.pause() }
    func resume() { recording.resume() }
    func stop() { recording.stop() }
    func prepareProcessingTracking() async {
        await recording.prepareProcessingTracking()
        alignTrackingSelectionWithActiveCourse()
    }
    func reloadProcessingTracking() async {
        await recording.reloadProcessingTracking()
        alignTrackingSelectionWithActiveCourse()
    }
    func selectProcessingJob(_ id: ProcessingJobID?) {
        guard let id, let job = processingJobs.first(where: { $0.id == id }) else {
            recording.selectProcessingJob(nil)
            return
        }
        activateTrackedCourse(job, navigateToTranscription: false)
    }
    func openSelectedCourseInLocalTranscription() {
        guard let job = selectedProcessingJob else { return }
        activateTrackedCourse(job, navigateToTranscription: true)
    }
    func finalizeForTermination() throws { try recording.finalizeForTermination() }

    var transcriptDraft: TranscriptDraft? {
        guard transcription.transcriptDraft?.courseID == activeCourseID else { return nil }
        return transcription.transcriptDraft
    }
    var transcriptSearch: String {
        get { transcription.transcriptSearch }
        set { transcription.transcriptSearch = newValue }
    }
    var transcriptFilter: TranscriptPassageFilter {
        get { transcription.transcriptFilter }
        set { transcription.transcriptFilter = newValue }
    }
    var selectedLocalTranscriptionModel: LocalTranscriptionModelID { transcription.selectedModel }
    var localModelStatus: TranscriptionModelStatus { transcription.modelStatus }
    var localTranscriptionProgress: LocalTranscriptionProgress { transcription.progress }
    var lastLocalTranscriptionResult: LocalTranscriptionResult? {
        guard transcription.lastResult?.courseID == activeCourseID else { return nil }
        return transcription.lastResult
    }
    var isDownloadingTranscriptionModel: Bool { transcription.isDownloadingModel }
    var isLocalTranscriptionRunning: Bool { transcription.isRunning }
    var isRetranscribingAudio: Bool { transcription.isRetranscribing }
    var hasPendingTranscriptionReplacement: Bool { transcription.pendingReplacement != nil }
    var localTranscriptionModels: [TranscriptionModelDescriptor] { transcription.models }
    var selectedLocalTranscriptionModelDescriptor: TranscriptionModelDescriptor {
        transcription.selectedModelDescriptor
    }
    var localAudioDuration: TimeInterval { transcription.audioDuration(for: capturedSegments) }
    var localTranscriptionForExport: StoredLocalTranscription? {
        transcription.transcriptionForExport(course: currentCourse, segments: capturedSegments)
    }
    var canStartLocalTranscription: Bool {
        existingAudioIssues.isEmpty
            && transcription.canStart(course: currentCourse, segments: capturedSegments)
    }
    var canRetranscribeAudio: Bool {
        lastLocalTranscriptionResult != nil && canStartLocalTranscription
    }
    var filteredTranscriptPassages: [TranscriptPassage] {
        transcriptDraft == nil ? [] : transcription.filteredPassages
    }
    var activeCourseTitle: String? {
        currentCourse?.title
            ?? processingJobs.first(where: { $0.courseID == activeCourseID })?.courseTitle
    }
    var activeCourseTeachingUnit: String? {
        currentCourse?.teachingUnit.displayName
            ?? processingJobs.first(where: { $0.courseID == activeCourseID })?.teachingUnit
    }
    var activeCourseTeacherName: String? { currentCourse?.teacherName }
    var activeCourseDate: Date? {
        currentCourse?.courseDate
            ?? processingJobs.first(where: { $0.courseID == activeCourseID })?.courseDate
    }
    func transcriptTextBinding(for passageID: UUID) -> Binding<String> {
        transcription.transcriptTextBinding(for: passageID)
    }
    func updateTranscriptPassage(id: UUID, text: String) {
        transcription.updatePassage(id: id, text: text)
        privacyReview = nil
    }
    func toggleTranscriptFlag(_ flag: TranscriptPassageFlag, passageID: UUID) {
        transcription.toggleFlag(flag, passageID: passageID)
        privacyReview = nil
    }
    func saveTranscript() { transcription.saveTranscript() }
    func selectLocalTranscriptionModel(_ id: LocalTranscriptionModelID) {
        transcription.selectModel(id)
    }
    func refreshLocalModelStatus() async { await transcription.refreshModelStatus() }
    func downloadSelectedTranscriptionModel() { transcription.downloadSelectedModel() }
    func cancelModelDownload() { transcription.cancelModelDownload() }
    func startLocalTranscription() {
        transcription.start(
            course: currentCourse, segments: capturedSegments,
            supportDocuments: supportDocuments.compactMap(\.extraction))
    }
    func retranscribeAudio() {
        guard existingAudioIssues.isEmpty else {
            errorMessage = existingAudioIssues.map(\.localizedDescription).joined(separator: " ")
            return
        }
        transcription.retranscribe(
            course: currentCourse, segments: capturedSegments,
            supportDocuments: supportDocuments.compactMap(\.extraction))
    }
    func confirmTranscriptionReplacement() {
        transcription.confirmPendingReplacement(courseID: currentCourse?.id)
    }
    func keepExistingTranscription() {
        transcription.keepExistingTranscription(courseID: currentCourse?.id)
    }
    func cancelLocalTranscription() { transcription.cancel(courseID: currentCourse?.id) }
    func openRawTranscriptInEditor() {
        if transcription.openRawTranscript() { selectedSection = .transcript }
    }

    private func activateTrackedCourse(
        _ job: ProcessingJob, navigateToTranscription: Bool
    ) {
        if activeCourseID == job.courseID,
           (hasActiveSession || isLocalTranscriptionRunning || hasPendingTranscriptionReplacement) {
            recording.selectProcessingJob(job.id)
            activeCourseSelection.select(job)
            if navigateToTranscription { selectedSection = .localTranscription }
            return
        }
        let changingCourse = activeCourseID != job.courseID
        if changingCourse && (hasActiveSession || isLocalTranscriptionRunning
            || hasPendingTranscriptionReplacement) {
            alignTrackingSelectionWithActiveCourse()
            errorMessage = hasPendingTranscriptionReplacement
                ? "Choisissez d’abord quelle transcription conserver avant de changer de cours."
                : "Terminez ou annulez le traitement en cours avant de changer de cours."
            return
        }

        recording.selectProcessingJob(job.id)
        activeCourseSelection.select(job)
        privacyReview = nil
        isLoadingActiveCourse = true
        activeCourseLoadTask?.cancel()
        let operationID = activeCourseLoadGeneration.begin()
        let session: RecoveredRecordingSession?
        do {
            session = try recording.recordingSession(for: job.courseID)
        } catch {
            _ = activeCourseLoadGeneration.finish(operationID)
            isLoadingActiveCourse = false
            errorMessage = "Les enregistrements de ce cours n’ont pas pu être chargés : \(error.localizedDescription)"
            return
        }

        activeCourseLoadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if activeCourseLoadGeneration.finish(operationID) {
                    isLoadingActiveCourse = false
                    activeCourseLoadTask = nil
                }
            }
            do {
                let stored = try await transcription.storedTranscription(for: job.courseID)
                try Task.checkCancellation()
                guard activeCourseLoadGeneration.accepts(operationID),
                      activeCourseID == job.courseID else { return }
                let workspace = try ActiveCourseWorkspace(
                    courseID: job.courseID,
                    recordingSession: session,
                    transcription: stored)
                recording.activate(workspace)
                transcription.activate(workspace.transcription)
                if navigateToTranscription { selectedSection = .localTranscription }
                workspaceNotice = !capturedSegments.isEmpty && existingAudioIssues.isEmpty
                    ? "\(job.courseTitle) est maintenant le cours actif."
                    : "\(job.courseTitle) est actif, mais aucun enregistrement exploitable n’est disponible."
            } catch is CancellationError {
                return
            } catch {
                guard activeCourseLoadGeneration.accepts(operationID) else { return }
                errorMessage = "Le cours sélectionné n’a pas pu être ouvert : \(error.localizedDescription)"
            }
        }
    }

    private func alignTrackingSelectionWithActiveCourse() {
        guard let activeCourseID,
              let job = processingJobs.first(where: { $0.courseID == activeCourseID }) else {
            return
        }
        recording.selectProcessingJob(job.id)
        activeCourseSelection.select(job)
    }

    private func cancelActiveCourseLoad() {
        activeCourseLoadTask?.cancel()
        activeCourseLoadTask = nil
        _ = activeCourseLoadGeneration.cancelCurrent()
        isLoadingActiveCourse = false
    }

    private var privacyContent: String {
        (transcriptDraft?.plainText ?? "") + "\n"
            + supportDocuments.compactMap(\.extraction?.plainText).joined(separator: "\n")
    }
    var privacyFindings: [PrivacyFinding] {
        transcriptDraft == nil ? [] : privacyDetector.scan(privacyContent)
    }
    var transcriptFingerprint: String? {
        transcriptDraft == nil ? nil : transcriptService.stableFingerprint(privacyContent)
    }
    var cloudTransmissionDecision: CloudTransmissionDecision? {
        guard let transcriptFingerprint else { return nil }
        return privacyGate.evaluate(
            text: privacyContent, contentFingerprint: transcriptFingerprint, review: privacyReview)
    }
    var isPrivacyApproved: Bool {
        switch cloudTransmissionDecision {
        case .allowedNoIdentifiers, .allowedAfterManualReview: true
        default: false
        }
    }
    var aiModelProfiles: [AIModelProfile] { AIModelCatalog.profiles }
    var selectedAIModelProfile: AIModelProfile {
        AIModelCatalog.profile(id: aiPreferences.selectedModelProfileID)
            ?? AIModelCatalog.profiles[0]
    }
    func approvePrivacyReview() {
        guard let transcriptFingerprint, !privacyFindings.isEmpty else { return }
        privacyReview = PrivacyReview(
            contentFingerprint: transcriptFingerprint, decision: .approved)
        workspaceNotice = "Vérification enregistrée pour cette version exacte de la transcription."
    }
    func rejectPrivacyReview() {
        guard let transcriptFingerprint else { return }
        privacyReview = PrivacyReview(
            contentFingerprint: transcriptFingerprint, decision: .rejected)
        selectedSection = .transcript
    }
    func importTeacherDocument() {
        let panel = NSOpenPanel()
        panel.title = "Importer un document fourni par l’enseignant"
        panel.message = "Le fichier sera copié dans le stockage local de Scrib."
        panel.prompt = "Importer"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            "doc", "docx", "pdf", "ppt", "pptx", "xls", "xlsx", "png", "jpg", "jpeg", "heic",
            "tiff",
        ].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url, !isImportingSupportDocument else {
            return
        }
        isImportingSupportDocument = true
        Task { [weak self] in
            guard let self else { return }
            defer { isImportingSupportDocument = false }
            do {
                let document = try await supportImporter.importDocument(from: url)
                supportDocuments = try await supportImporter.documents()
                workspaceNotice = "\(document.originalFileName) a été copié dans Scrib."
            } catch {
                errorMessage = "Le document n’a pas pu être importé : \(error.localizedDescription)"
            }
        }
    }
    func deleteSupportDocument(_ document: SupportDocument) {
        guard !isDeletingSupportDocument else { return }
        isDeletingSupportDocument = true
        Task { [weak self] in
            guard let self else { return }
            defer { isDeletingSupportDocument = false }
            do {
                try await supportImporter.deleteDocument(id: document.id)
                supportDocuments = try await supportImporter.documents()
            } catch {
                errorMessage =
                    "Le document n’a pas pu être supprimé : \(error.localizedDescription)"
            }
        }
    }
    func openSupportDocument(_ document: SupportDocument) {
        guard let url = document.localURL else {
            workspaceNotice = "Le fichier local de ce document est indisponible."
            return
        }
        NSWorkspace.shared.open(url)
    }
    private func refreshSupportDocuments() async {
        do { supportDocuments = try await supportImporter.documents() } catch {
            errorMessage =
                "Les documents importés n’ont pas pu être lus : \(error.localizedDescription)"
        }
    }
    func selectAIModel(_ id: String) {
        guard AIModelCatalog.profile(id: id) != nil else { return }
        aiPreferences.selectedModelProfileID = id
        persistAIPreferences()
        aiAPIKeyDraft = ""
        scheduleAIKeyStatusRefresh()
    }
    func setAITrialBudget(_ value: Double) {
        aiPreferences.trialBudgetUSD = min(max(value, 0), 100)
        persistAIPreferences()
    }
    func setAILiveRequestsEnabled(_ enabled: Bool) {
        aiPreferences.liveRequestsEnabled = enabled
        persistAIPreferences()
    }
    func saveAIAPIKey() {
        let key = aiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedAIModelProfile.isLive else { return }
        guard key.count >= 20 else {
            errorMessage = "La clé API semble incomplète."
            return
        }
        let provider = selectedAIModelProfile.provider
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await aiSecretStore.saveSecret(key, for: provider)
                aiAPIKeyDraft = ""
                aiHasStoredKey = true
                workspaceNotice =
                    "Clé enregistrée dans le Trousseau macOS. Aucun appel n’a été effectué."
            } catch {
                errorMessage = "La clé n’a pas pu être enregistrée : \(error.localizedDescription)"
            }
        }
    }
    func deleteAIAPIKey() {
        let provider = selectedAIModelProfile.provider
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await aiSecretStore.deleteSecret(for: provider)
                aiHasStoredKey = false
                aiAPIKeyDraft = ""
                aiPreferences.liveRequestsEnabled = false
                persistAIPreferences()
                workspaceNotice = "La clé API a été supprimée du Trousseau."
            } catch {
                errorMessage = "La clé n’a pas pu être supprimée : \(error.localizedDescription)"
            }
        }
    }
    private func refreshAIKeyStatus() async {
        let provider = selectedAIModelProfile.provider
        let id = aiKeyStatusGeneration.begin()
        do {
            let hasKey = try await aiSecretStore.hasSecret(for: provider)
            guard aiKeyStatusGeneration.finish(id), selectedAIModelProfile.provider == provider
            else {
                return
            }
            aiHasStoredKey = hasKey
        } catch {
            guard aiKeyStatusGeneration.finish(id), selectedAIModelProfile.provider == provider,
                !Task.isCancelled
            else { return }
            aiHasStoredKey = false
            errorMessage =
                "Le Trousseau macOS n’a pas pu être consulté : \(error.localizedDescription)"
        }
    }
    private func scheduleAIKeyStatusRefresh() {
        aiKeyStatusTask?.cancel()
        aiKeyStatusTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await refreshAIKeyStatus()
        }
    }
    private func persistAIPreferences() {
        do { try aiPreferencesStore.save(aiPreferences) } catch {
            errorMessage =
                "Les réglages IA n’ont pas pu être enregistrés : \(error.localizedDescription)"
        }
    }
    func presentQuitWarning() { quitWarningRequested = true }
    func confirmQuitAndStop() {
        do {
            if hasActiveSession { try finalizeForTermination() }
            NSApplication.shared.terminate(nil)
        } catch {
            errorMessage =
                "Impossible de terminer l'enregistrement avant de quitter : \(error.localizedDescription)"
        }
    }
    func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    var formattedElapsed: String {
        let seconds = Int(snapshot.elapsed.rounded(.down))
        return String(
            format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }
    var menuBarSystemImage: String {
        if recordingWorkflowState == .error { return "exclamationmark.triangle.fill" }
        if isStartingRecording || isStoppingRecording { return "hourglass" }
        if isRecording { return "record.circle.fill" }
        if isPaused { return "pause.circle.fill" }
        return "waveform"
    }
    var menuBarStatus: String {
        if recordingWorkflowState == .error { return "L'enregistrement nécessite votre attention" }
        if isStartingRecording { return "Démarrage de l'enregistrement…" }
        if isStoppingRecording { return "Finalisation de l'enregistrement…" }
        if isRecording { return "Enregistrement — \(formattedElapsed)" }
        if isPaused { return "En pause — \(formattedElapsed)" }
        return "Scrib est prêt"
    }
}
