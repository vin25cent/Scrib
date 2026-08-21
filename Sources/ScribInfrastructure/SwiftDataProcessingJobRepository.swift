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
    var activityRaw: String
    var statusRaw: String
    var reportedProgress: Double?
    var suspensionReason: String?
    var lastError: String?

    init(job: ProcessingJob) throws {
        id = job.id.rawValue
        courseID = job.courseID.rawValue
        courseTitle = job.courseTitle
        teachingUnit = job.teachingUnit
        courseDate = job.courseDate
        createdAt = job.createdAt
        updatedAt = job.updatedAt
        activityRaw = job.activity.rawValue
        statusRaw = job.status.rawValue
        reportedProgress = job.reportedProgress
        suspensionReason = job.suspensionReason
        lastError = job.lastError
    }

    func update(from job: ProcessingJob) throws {
        courseID = job.courseID.rawValue
        courseTitle = job.courseTitle
        teachingUnit = job.teachingUnit
        courseDate = job.courseDate
        createdAt = job.createdAt
        updatedAt = job.updatedAt
        activityRaw = job.activity.rawValue
        statusRaw = job.status.rawValue
        reportedProgress = job.reportedProgress
        suspensionReason = job.suspensionReason
        lastError = job.lastError
    }

    func domainValue() throws -> ProcessingJob {
        guard let activity = ProcessingActivity(rawValue: activityRaw) else {
            throw SwiftDataProcessingRepositoryError.invalidStoredActivity(activityRaw)
        }
        guard let status = ProcessingStatus(rawValue: statusRaw) else {
            throw SwiftDataProcessingRepositoryError.invalidStoredStatus(statusRaw)
        }
        return ProcessingJob(
            id: ProcessingJobID(rawValue: id),
            courseID: CourseID(rawValue: courseID),
            courseTitle: courseTitle,
            teachingUnit: teachingUnit,
            courseDate: courseDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            activity: activity,
            status: status,
            reportedProgress: reportedProgress,
            suspensionReason: suspensionReason,
            lastError: lastError,
        )
    }
}

public enum SwiftDataProcessingRepositoryError: Error {
    case invalidStoredActivity(String)
    case invalidStoredStatus(String)
}

public actor SwiftDataProcessingJobRepository: ProcessingJobRepository {
    private let container: ModelContainer

    public init(inMemory: Bool = false) throws {
        let schema = Schema([StoredProcessingJob.self])
        let configuration = ModelConfiguration(
            // The former queue store described a pipeline that did not run.
            // Keeping a distinct store prevents those stale claims from being
            // presented as current activity.
            "ScribProcessingTracking",
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
