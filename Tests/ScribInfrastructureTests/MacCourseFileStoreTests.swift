#if os(macOS)
import Foundation
import Testing
@testable import ScribDomain
@testable import ScribInfrastructure

@MainActor
struct MacCourseFileStoreTests {
    @Test func resolvesDifferentRootDirectoriesForDifferentCourses() throws {
        let fixture = try Fixture()
        let firstCourse = CourseID()
        let secondCourse = CourseID()

        let firstDirectory = try fixture.store.courseDirectory(for: firstCourse)
        let secondDirectory = try fixture.store.courseDirectory(for: secondCourse)

        #expect(firstDirectory != secondDirectory)
        #expect(firstDirectory.lastPathComponent == firstCourse.rawValue.uuidString)
        #expect(secondDirectory.lastPathComponent == secondCourse.rawValue.uuidString)
        #expect(FileManager.default.fileExists(atPath: firstDirectory.path))
        #expect(FileManager.default.fileExists(atPath: secondDirectory.path))
    }

    @Test func createsMissingCourseRootWithoutCreatingCourseData() throws {
        let fixture = try Fixture()
        let courseID = CourseID()
        let expectedDirectory = fixture.rootDirectory
            .appendingPathComponent("Scrib", isDirectory: true)
            .appendingPathComponent("Courses", isDirectory: true)
            .appendingPathComponent(courseID.rawValue.uuidString, isDirectory: true)

        #expect(!FileManager.default.fileExists(atPath: expectedDirectory.path))
        let directory = try fixture.store.courseDirectory(for: courseID)

        #expect(directory == expectedDirectory)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func returnsExistingCourseRootAndKeepsItsContents() throws {
        let fixture = try Fixture()
        let courseID = CourseID()
        let directory = try fixture.store.courseDirectory(for: courseID)
        let manifest = directory.appendingPathComponent("recording-session.json")
        try Data("{}".utf8).write(to: manifest)

        let resolvedAgain = try fixture.store.courseDirectory(for: courseID)

        #expect(resolvedAgain == directory)
        #expect(FileManager.default.fileExists(atPath: manifest.path))
    }

    @Test func surfacesStorageCreationErrors() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScribCourseFileStoreFailureTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let blockingFile = rootDirectory.appendingPathComponent("Scrib")
        #expect(FileManager.default.createFile(atPath: blockingFile.path, contents: Data()))
        let store = MacCourseFileStore(applicationSupportDirectory: rootDirectory)

        #expect(throws: (any Error).self) {
            try store.courseDirectory(for: CourseID())
        }
    }
}

@MainActor
private final class Fixture {
    let rootDirectory: URL
    let store: MacCourseFileStore

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScribCourseFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        store = MacCourseFileStore(applicationSupportDirectory: rootDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
#endif
