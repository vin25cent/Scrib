#if os(macOS)
import Foundation
import ScribApplication
import ScribDomain

@MainActor
public final class MacCourseFileStore: CourseFileStoring {
    private let fileManager: FileManager
    private let applicationSupportDirectory: URL

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
    }

    init(applicationSupportDirectory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    public func courseDirectory(for courseID: CourseID) throws -> URL {
        let directory = applicationSupportDirectory
            .appendingPathComponent("Scrib", isDirectory: true)
            .appendingPathComponent("Courses", isDirectory: true)
            .appendingPathComponent(courseID.rawValue.uuidString, isDirectory: true)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    public func recordingDirectory(for course: Course) throws -> URL {
        let directory = try courseDirectory(for: course.id)
            .appendingPathComponent("audio", isDirectory: true)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    public func availableCapacity(for directory: URL) throws -> Int64 {
        let values = try directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
#endif
