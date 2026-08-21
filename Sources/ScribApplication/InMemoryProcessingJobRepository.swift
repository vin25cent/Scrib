import ScribDomain

public actor InMemoryProcessingJobRepository: ProcessingJobRepository {
    private var storage: [ProcessingJobID: ProcessingJob]

    public init(jobs: [ProcessingJob] = []) {
        self.storage = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
    }

    public func save(_ job: ProcessingJob) {
        storage[job.id] = job
    }

    public func job(id: ProcessingJobID) -> ProcessingJob? {
        storage[id]
    }

    public func jobs() -> [ProcessingJob] {
        storage.values.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
    }

    public func delete(id: ProcessingJobID) {
        storage[id] = nil
    }
}
