import Foundation

public struct ProcessingJobID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum ProcessingStage: String, Codable, CaseIterable, Sendable {
    case preparing
    case normalizingAudio
    case transcribing
    case analyzing
    case rendering
    case publishing

    public var displayName: String {
        switch self {
        case .preparing: "Préparation"
        case .normalizingAudio: "Normalisation audio"
        case .transcribing: "Transcription"
        case .analyzing: "Analyse et structuration"
        case .rendering: "Création des documents"
        case .publishing: "Publication iCloud"
        }
    }
}

public enum CourseStatus: String, Codable, Sendable {
    case draft
    case recording
    case captured
    case queued
    case processing
    case suspended
    case needsAttention
    case completed

    public var displayName: String {
        switch self {
        case .draft: "Brouillon"
        case .recording: "Enregistrement"
        case .captured: "Capturé"
        case .queued: "En attente"
        case .processing: "Traitement"
        case .suspended: "Suspendu"
        case .needsAttention: "Action nécessaire"
        case .completed: "Terminé"
        }
    }
}

public struct ProcessingCheckpoint: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let stage: ProcessingStage
    public let completedAt: Date
    public let outputFingerprint: String?

    public init(
        id: UUID = UUID(),
        stage: ProcessingStage,
        completedAt: Date = Date(),
        outputFingerprint: String? = nil
    ) {
        self.id = id
        self.stage = stage
        self.completedAt = completedAt
        self.outputFingerprint = outputFingerprint
    }
}

public struct ProcessingJob: Identifiable, Equatable, Codable, Sendable {
    public let id: ProcessingJobID
    public let courseID: CourseID
    public var courseTitle: String
    public var teachingUnit: String
    public var courseDate: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var status: CourseStatus
    public var stage: ProcessingStage?
    public var progress: Double
    public var attemptCount: Int
    public var nextAttemptAt: Date?
    public var lastError: String?
    public var suspensionReasons: [ProcessingBlocker]
    public var checkpoints: [ProcessingCheckpoint]

    public init(
        id: ProcessingJobID = ProcessingJobID(),
        courseID: CourseID,
        courseTitle: String = "",
        teachingUnit: String = "",
        courseDate: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: CourseStatus = .draft,
        stage: ProcessingStage? = nil,
        progress: Double = 0,
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastError: String? = nil,
        suspensionReasons: [ProcessingBlocker] = [],
        checkpoints: [ProcessingCheckpoint] = []
    ) {
        self.id = id
        self.courseID = courseID
        self.courseTitle = courseTitle
        self.teachingUnit = teachingUnit
        self.courseDate = courseDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.stage = stage
        self.progress = min(max(progress, 0), 1)
        self.attemptCount = max(attemptCount, 0)
        self.nextAttemptAt = nextAttemptAt
        self.lastError = lastError
        self.suspensionReasons = suspensionReasons
        self.checkpoints = checkpoints
    }

    public init(course: Course, createdAt: Date = Date()) {
        self.init(
            courseID: course.id,
            courseTitle: course.title,
            teachingUnit: course.teachingUnit.displayName,
            courseDate: course.courseDate,
            createdAt: createdAt,
            updatedAt: createdAt,
            status: .queued
        )
    }

    public var nextStage: ProcessingStage? {
        ProcessingStage.allCases.first { stage in
            !checkpoints.contains { $0.stage == stage }
        }
    }

    public mutating func completeStage(
        _ completedStage: ProcessingStage,
        outputFingerprint: String? = nil,
        at date: Date = Date()
    ) {
        checkpoints.removeAll { $0.stage == completedStage }
        checkpoints.append(
            ProcessingCheckpoint(
                stage: completedStage,
                completedAt: date,
                outputFingerprint: outputFingerprint
            )
        )
        let completed = Double(Set(checkpoints.map(\.stage)).count)
        progress = min(completed / Double(ProcessingStage.allCases.count), 1)
        updatedAt = date
        stage = nextStage ?? completedStage
    }
}

public enum ThermalCondition: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

public enum MemoryCondition: String, Codable, Sendable {
    case normal
    case warning
    case critical
}

public enum ProcessingBlocker: String, Codable, CaseIterable, Sendable {
    case recordingActive
    case batteryPower
    case networkUnavailable
    case thermalPressure
    case memoryPressure

    public var displayName: String {
        switch self {
        case .recordingActive: "Enregistrement prioritaire"
        case .batteryPower: "Mac non branché"
        case .networkUnavailable: "Internet indisponible"
        case .thermalPressure: "Température élevée"
        case .memoryPressure: "Pression mémoire"
        }
    }
}

public struct SystemConditionSnapshot: Equatable, Codable, Sendable {
    public var isOnExternalPower: Bool
    public var isNetworkAvailable: Bool
    public var thermalCondition: ThermalCondition
    public var memoryCondition: MemoryCondition
    public var isRecordingActive: Bool
    public var capturedAt: Date

    public init(
        isOnExternalPower: Bool,
        isNetworkAvailable: Bool,
        thermalCondition: ThermalCondition = .nominal,
        memoryCondition: MemoryCondition = .normal,
        isRecordingActive: Bool = false,
        capturedAt: Date = Date()
    ) {
        self.isOnExternalPower = isOnExternalPower
        self.isNetworkAvailable = isNetworkAvailable
        self.thermalCondition = thermalCondition
        self.memoryCondition = memoryCondition
        self.isRecordingActive = isRecordingActive
        self.capturedAt = capturedAt
    }

    public var blockers: [ProcessingBlocker] {
        var values: [ProcessingBlocker] = []
        if isRecordingActive { values.append(.recordingActive) }
        if !isOnExternalPower { values.append(.batteryPower) }
        if !isNetworkAvailable { values.append(.networkUnavailable) }
        if thermalCondition == .serious || thermalCondition == .critical {
            values.append(.thermalPressure)
        }
        if memoryCondition != .normal { values.append(.memoryPressure) }
        return values
    }

    public var canRunHeavyProcessing: Bool { blockers.isEmpty }
}
