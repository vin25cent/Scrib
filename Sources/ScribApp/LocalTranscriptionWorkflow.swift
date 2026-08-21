import Combine
import Foundation
import ScribApplication
import ScribDomain
import SwiftUI

/// Runs local model management, transcription, and the editable transcript workspace.
@MainActor
final class LocalTranscriptionWorkflow: ObservableObject {
    @Published var transcriptDraft: TranscriptDraft?
    @Published var transcriptSearch = ""
    @Published var transcriptFilter: TranscriptPassageFilter = .all
    @Published var selectedModel: LocalTranscriptionModelID = .tinyMultilingual
    @Published private(set) var modelStatus = TranscriptionModelStatus(
        modelID: .tinyMultilingual, availability: .notDownloaded)
    @Published private(set) var progress = LocalTranscriptionProgress(stage: .idle)
    @Published private(set) var lastResult: LocalTranscriptionResult?
    @Published private(set) var isDownloadingModel = false
    @Published private(set) var isRunning = false

    var reportError: @MainActor (String) -> Void = { _ in }
    var reportNotice: @MainActor (String) -> Void = { _ in }
    var trackingDidChange: @MainActor () async -> Void = {}

    private let coordinator: LocalTranscriptionCoordinator
    private let processingTracker: ProcessingActivityTracker
    private let transcriptService = TranscriptWorkspaceService()
    private var realDraft: TranscriptDraft?
    private var modelDownloadTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var retiringModelDownloadTask: (id: UUID, task: Task<Void, Never>)?
    private var retiringTranscriptionTask: (id: UUID, task: Task<Void, Never>)?
    private var saveTask: Task<Void, Never>?
    private var modelStatusTask: Task<Void, Never>?
    private var transcriptionGeneration = LatestOperationGeneration()
    private var modelDownloadGeneration = LatestOperationGeneration()
    private var modelStatusGeneration = LatestOperationGeneration()
    private var saveGeneration = LatestOperationGeneration()
    private var transcriptionProgressGate = OrderedProgressGate()
    private var modelDownloadProgressGate = OrderedProgressGate()

    init(coordinator: LocalTranscriptionCoordinator, processingTracker: ProcessingActivityTracker) {
        self.coordinator = coordinator
        self.processingTracker = processingTracker
    }

    var models: [TranscriptionModelDescriptor] { LocalTranscriptionModelCatalog.alphaModels }
    var selectedModelDescriptor: TranscriptionModelDescriptor {
        LocalTranscriptionModelCatalog.descriptor(for: selectedModel)
            ?? LocalTranscriptionModelCatalog.alphaModels[0]
    }
    var filteredPassages: [TranscriptPassage] {
        guard let transcriptDraft else { return [] }
        return transcriptService.passages(
            in: transcriptDraft, matching: transcriptSearch, filter: transcriptFilter)
    }
    func canStart(course: Course?, segments: [RecordingSegment]) -> Bool {
        course != nil && !segments.isEmpty && modelStatus.availability == .available && !isRunning
            && !isDownloadingModel
    }
    func audioDuration(for segments: [RecordingSegment]) -> TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }
    func transcriptionForExport(course: Course?, segments: [RecordingSegment])
        -> StoredLocalTranscription?
    {
        guard let course, let lastResult, let realDraft else { return nil }
        return StoredLocalTranscription(
            course: course, recordingSegments: segments, result: lastResult, draft: realDraft)
    }

    func resetForNewRecording() {
        progress = .init(stage: .idle)
        lastResult = nil
        realDraft = nil
        transcriptDraft = nil
    }

    func restoreLatest() async -> StoredLocalTranscription? {
        do {
            guard let stored = try await coordinator.latestTranscription() else { return nil }
            lastResult = stored.result
            realDraft = stored.draft
            transcriptDraft = stored.draft
            return stored
        } catch {
            reportError(
                "La dernière transcription locale n’a pas pu être restaurée : \(error.localizedDescription)"
            )
            return nil
        }
    }

    func transcriptTextBinding(for passageID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.transcriptDraft?.passages.first(where: { $0.id == passageID })?.text ?? ""
            }, set: { [weak self] value in self?.updatePassage(id: passageID, text: value) })
    }
    func updatePassage(id: UUID, text: String) {
        guard let transcriptDraft else { return }
        self.transcriptDraft = transcriptService.updating(
            transcriptDraft, passageID: id, text: text)
    }
    func toggleFlag(_ flag: TranscriptPassageFlag, passageID: UUID) {
        guard let transcriptDraft else { return }
        self.transcriptDraft = transcriptService.toggling(
            flag, in: transcriptDraft, passageID: passageID)
    }
    func saveTranscript() {
        guard var draft = transcriptDraft else { return }
        draft.updatedAt = Date()
        transcriptDraft = draft
        persistEditedDraft(draft)
        reportNotice("Transcription enregistrée localement.")
    }
    func openRawTranscript() -> Bool {
        guard let realDraft else { return false }
        transcriptDraft = realDraft
        return true
    }

    func selectModel(_ modelID: LocalTranscriptionModelID) {
        guard LocalTranscriptionModelCatalog.descriptor(for: modelID)?.isEnabledInAlpha == true
        else {
            return
        }
        cancelModelDownload()
        selectedModel = modelID
        modelStatus = .init(modelID: modelID, availability: .notDownloaded)
        scheduleModelStatusRefresh()
    }
    func refreshModelStatus() async {
        let modelID = selectedModel
        let id = modelStatusGeneration.begin()
        let status = await coordinator.modelStatus(for: modelID)
        guard modelStatusGeneration.finish(id), selectedModel == modelID, !isDownloadingModel else {
            return
        }
        modelStatus = status
    }
    func downloadSelectedModel() {
        guard !isDownloadingModel else { return }
        _ = modelStatusGeneration.cancelCurrent()
        isDownloadingModel = true
        let modelID = selectedModel
        let id = modelDownloadGeneration.begin()
        let sequence = WorkflowProgressSequence()
        let predecessor = retiringModelDownloadTask
        modelDownloadProgressGate.begin(operationID: id)
        modelDownloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if retiringModelDownloadTask?.id == id { retiringModelDownloadTask = nil }
                if modelDownloadGeneration.finish(id) {
                    modelDownloadProgressGate.invalidate(operationID: id)
                    isDownloadingModel = false
                    modelDownloadTask = nil
                }
            }
            do {
                if let predecessor {
                    await predecessor.task.value
                    if retiringModelDownloadTask?.id == predecessor.id {
                        retiringModelDownloadTask = nil
                    }
                }
                try Task.checkCancellation()
                guard modelDownloadGeneration.accepts(id) else { return }
                let status = try await coordinator.downloadModel(modelID) { [weak self] status in
                    let callbackSequence = sequence.next()
                    Task { @MainActor [weak self] in
                        self?.applyModelDownloadProgress(
                            status, operationID: id, sequence: callbackSequence)
                    }
                }
                guard modelDownloadGeneration.accepts(id), !Task.isCancelled else { return }
                modelStatus = status
                reportNotice(
                    "Le modèle \(selectedModelDescriptor.displayName) est disponible hors ligne.")
            } catch is CancellationError {
                guard modelDownloadGeneration.accepts(id) else { return }
                let status = await coordinator.modelStatus(for: modelID)
                guard modelDownloadGeneration.accepts(id), selectedModel == modelID,
                    !Task.isCancelled
                else { return }
                modelStatus = status
            } catch {
                guard modelDownloadGeneration.accepts(id), !Task.isCancelled else { return }
                modelStatus = .init(
                    modelID: modelID, availability: .failed,
                    errorMessage: error.localizedDescription)
                reportError(error.localizedDescription)
            }
        }
    }
    func cancelModelDownload() {
        if let modelDownloadTask, let id = modelDownloadGeneration.currentID {
            modelDownloadTask.cancel()
            retiringModelDownloadTask = (id, modelDownloadTask)
        }
        if let id = modelDownloadGeneration.currentID {
            modelDownloadProgressGate.invalidate(operationID: id)
        }
        _ = modelDownloadGeneration.cancelCurrent()
        modelDownloadTask = nil
        isDownloadingModel = false
    }

    func start(course: Course?, segments: [RecordingSegment]) {
        guard let course, canStart(course: course, segments: segments) else { return }
        let modelID = selectedModel
        let id = transcriptionGeneration.begin()
        let sequence = WorkflowProgressSequence()
        let predecessor = retiringTranscriptionTask
        transcriptionProgressGate.begin(operationID: id)
        isRunning = true
        progress = .init(
            stage: .checkingModel, fractionCompleted: 0, totalSegmentCount: segments.count)
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if retiringTranscriptionTask?.id == id { retiringTranscriptionTask = nil }
                if transcriptionGeneration.finish(id) {
                    transcriptionProgressGate.invalidate(operationID: id)
                    isRunning = false
                    transcriptionTask = nil
                }
            }
            do {
                if let predecessor {
                    await predecessor.task.value
                    if retiringTranscriptionTask?.id == predecessor.id {
                        retiringTranscriptionTask = nil
                    }
                }
                try Task.checkCancellation()
                guard transcriptionGeneration.accepts(id) else { return }
                do {
                    _ = try await processingTracker.start(
                        course: course, activity: .localTranscription)
                    try await processingTracker.markRunning(
                        courseID: course.id, activity: .localTranscription, progress: 0)
                    await trackingDidChange()
                } catch {
                    reportError(
                        "La transcription continue, mais son suivi n’a pas pu être mis à jour : \(error.localizedDescription)"
                    )
                }
                let stored = try await coordinator.transcribe(
                    course: course, segments: segments, modelID: modelID
                ) { [weak self] update in
                    let callbackSequence = sequence.next()
                    Task { @MainActor [weak self] in
                        self?.applyProgress(
                            update, operationID: id, sequence: callbackSequence, courseID: course.id
                        )
                    }
                }
                guard transcriptionGeneration.accepts(id), !Task.isCancelled else { return }
                lastResult = stored.result
                realDraft = stored.draft
                transcriptDraft = stored.draft
                progress = .init(
                    stage: .completed, fractionCompleted: 1, completedSegmentCount: segments.count,
                    totalSegmentCount: segments.count,
                    elapsedSeconds: stored.result.metrics.processingDurationSeconds)
                do {
                    try await processingTracker.complete(
                        courseID: course.id, activity: .localTranscription)
                    await trackingDidChange()
                } catch {
                    reportError(
                        "La transcription est terminée, mais son suivi n’a pas pu être mis à jour : \(error.localizedDescription)"
                    )
                }
                reportNotice("Transcription brute terminée et enregistrée localement.")
            } catch is CancellationError {
                guard transcriptionGeneration.accepts(id) else { return }
                progress.stage = .cancelled
                progress.message = "Transcription annulée proprement."
                try? await processingTracker.suspend(
                    courseID: course.id, activity: .localTranscription,
                    reason: "Transcription annulée.")
                await trackingDidChange()
            } catch {
                guard transcriptionGeneration.accepts(id), !Task.isCancelled else { return }
                progress.stage = .failed
                progress.message = error.localizedDescription
                reportError("La transcription locale a échoué : \(error.localizedDescription)")
                try? await processingTracker.fail(
                    courseID: course.id, activity: .localTranscription,
                    error: error.localizedDescription)
                await trackingDidChange()
            }
        }
    }
    func cancel(courseID: CourseID?) {
        if let transcriptionTask, let id = transcriptionGeneration.currentID {
            transcriptionTask.cancel()
            retiringTranscriptionTask = (id, transcriptionTask)
        }
        if let id = transcriptionGeneration.currentID {
            transcriptionProgressGate.invalidate(operationID: id)
        }
        _ = transcriptionGeneration.cancelCurrent()
        transcriptionTask = nil
        isRunning = false
        progress.stage = .cancelled
        progress.message = "Transcription annulée."
        guard let courseID else { return }
        let tracker = processingTracker
        Task { [weak self] in
            try? await tracker.suspend(
                courseID: courseID, activity: .localTranscription, reason: "Transcription annulée.")
            await self?.trackingDidChange()
        }
    }

    private func persistEditedDraft(_ draft: TranscriptDraft) {
        realDraft = draft
        let predecessor = saveTask
        predecessor?.cancel()
        let id = saveGeneration.begin()
        saveTask = Task { [weak self] in
            guard let self else { return }
            defer { if saveGeneration.finish(id) { saveTask = nil } }
            do {
                if let predecessor { await predecessor.value }
                try Task.checkCancellation()
                guard saveGeneration.accepts(id) else { return }
                try await coordinator.saveEditedDraft(draft)
            } catch {
                guard saveGeneration.accepts(id), !Task.isCancelled else { return }
                reportError(
                    "La modification n’a pas pu être enregistrée : \(error.localizedDescription)")
            }
        }
    }
    private func scheduleModelStatusRefresh() {
        modelStatusTask?.cancel()
        modelStatusTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await refreshModelStatus()
        }
    }
    private func applyProgress(
        _ update: LocalTranscriptionProgress, operationID: UUID, sequence: Int, courseID: CourseID
    ) {
        guard transcriptionGeneration.accepts(operationID),
            transcriptionProgressGate.accept(operationID: operationID, sequence: sequence)
        else { return }
        progress = update
        guard let fractionCompleted = update.fractionCompleted else { return }
        let tracker = processingTracker
        let observedAt = Date()
        Task {
            try? await tracker.updateProgress(
                courseID: courseID, activity: .localTranscription,
                progress: fractionCompleted,
                at: observedAt)
        }
    }
    private func applyModelDownloadProgress(
        _ status: TranscriptionModelStatus, operationID: UUID, sequence: Int
    ) {
        guard modelDownloadGeneration.accepts(operationID), selectedModel == status.modelID,
            modelDownloadProgressGate.accept(operationID: operationID, sequence: sequence)
        else { return }
        modelStatus = status
    }
}
