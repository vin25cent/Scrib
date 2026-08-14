#if os(macOS)
import Foundation
import ScribApplication
import ScribDomain
import SwiftData

@Model
final class StoredProcessingJob {
    @Attribute(.unique) var id: UUID
    var courseID: UUID
    var courseTitle: String
    var teachingUnit: String
    var courseDate: Date
    var createdAt: Date
    var updatedAt: Date
    var statusRaw: String
    var stageRaw: String?
    var progress: Double
    var attemptCount: Int
    var nextAttemptAt: Date?
    var lastError: String?
    var suspensionReasonsData: Data
    var checkpointsData: Data

    init(job: ProcessingJob) throws {
        id = job.id.rawValue
        courseID = job.courseID.rawValue
        courseTitle = job.courseTitle
        teachingUnit = job.teachingUnit
        courseDate = job.courseDate
        createdAt = job.createdAt
        updatedAt = job.updatedAt
        statusRaw = job.status.rawValue
        stageRaw = job.stage?.rawValue
        progress = job.progress
        attemptCount = job.attemptCount
        nextAttemptAt = job.nextAttemptAt
        lastError = job.lastError
        suspensionReasonsData = try JSONEncoder().encode(job.suspensionReasons)
        checkpointsData = try JSONEncoder().encode(job.checkpoints)
    }

    func update(from job: ProcessingJob) throws {
        courseID = job.courseID.rawValue
        courseTitle = job.courseTitle
        teachingUnit = job.teachingUnit
        courseDate = job.courseDate
        createdAt = job.createdAt
        updatedAt = job.updatedAt
        statusRaw = job.status.rawValue
        stageRaw = job.stage?.rawValue
        progress = job.progress
        attemptCount = job.attemptCount
        nextAttemptAt = job.nextAttemptAt
        lastError = job.lastError
        suspensionReasonsData = try JSONEncoder().encode(job.suspensionReasons)
        checkpointsData = try JSONEncoder().encode(job.checkpoints)
    }

    func domainValue() throws -> ProcessingJob {
        guard let status = CourseStatus(rawValue: statusRaw) else {
            throw SwiftDataProcessingRepositoryError.invalidStoredStatus(statusRaw)
        }
        let stage = stageRaw.flatMap(ProcessingStage.init(rawValue:))
        return try ProcessingJob(
            id: ProcessingJobID(rawValue: id),
            courseID: CourseID(rawValue: courseID),
            courseTitle: courseTitle,
            teachingUnit: teachingUnit,
            courseDate: courseDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            status: status,
            stage: stage,
            progress: progress,
            attemptCount: attemptCount,
            nextAttemptAt: nextAttemptAt,
            lastError: lastError,
            suspensionReasons: JSONDecoder().decode(
                [ProcessingBlocker].self,
                from: suspensionReasonsData
            ),
            checkpoints: JSONDecoder().decode(
                [ProcessingCheckpoint].self,
                from: checkpointsData
            )
        )
    }
}

public enum SwiftDataProcessingRepositoryError: Error {
    case invalidStoredStatus(String)
}

public actor SwiftDataProcessingJobRepository: ProcessingJobRepository {
    private let container: ModelContainer

    public init(inMemory: Bool = false) throws {
        let schema = Schema([StoredProcessingJob.self])
        let configuration = ModelConfiguration(
            "ScribProcessingQueue",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    public func save(_ job: ProcessingJob) throws {
        let context = ModelContext(container)
        let stored = try context.fetch(FetchDescriptor<StoredProcessingJob>())
            .first { $0.id == job.id.rawValue }
        if let stored {
            try stored.update(from: job)
        } else {
            context.insert(try StoredProcessingJob(job: job))
        }
        try context.save()
    }

    public func job(id: ProcessingJobID) throws -> ProcessingJob? {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<StoredProcessingJob>())
            .first { $0.id == id.rawValue }?
            .domainValue()
    }

    public func jobs() throws -> [ProcessingJob] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<StoredProcessingJob>())
            .map { try $0.domainValue() }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
    }

    public func delete(id: ProcessingJobID) throws {
        let context = ModelContext(container)
        let matches = try context.fetch(FetchDescriptor<StoredProcessingJob>())
            .filter { $0.id == id.rawValue }
        matches.forEach(context.delete)
        if !matches.isEmpty {
            try context.save()
        }
    }
}
#endif
