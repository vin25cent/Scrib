import Foundation
import ScribDomain

public protocol CourseRepository: Sendable {
    func save(_ course: Course) async throws
    func course(id: CourseID) async throws -> Course?
}

public protocol AudioRecording: Sendable {
    func start(courseID: CourseID) async throws
    func stop() async throws
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(courseID: CourseID) async throws -> String
}

public protocol DocumentRendering: Sendable {
    func render(courseID: CourseID, transcript: String) async throws
}

public protocol SystemConditionsMonitoring: Sendable {
    var canRunHeavyProcessing: Bool { get async }
}
