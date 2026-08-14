import Foundation
import ScribDomain

public enum DeferredPipelineError: LocalizedError, Sendable {
    case stageNotImplemented(ProcessingStage)

    public var errorDescription: String? {
        switch self {
        case let .stageNotImplemented(stage):
            "L’étape « \(stage.displayName) » sera branchée dans une phase ultérieure."
        }
    }
}

public struct DeferredPipelineExecutor: PipelineStepExecuting {
    public init() {}

    public func execute(
        stage: ProcessingStage,
        courseID: CourseID
    ) async throws -> ProcessingStepResult {
        throw DeferredPipelineError.stageNotImplemented(stage)
    }
}
