import Foundation
import Testing
@testable import ScribDomain
@testable import ScribInfrastructure

@MainActor
struct LocalRecordingSessionStoreTests {
    @Test func manifestIsCreatedWhenSessionStarts() throws {
        let fixture = try Fixture()
        let manifest = try fixture.store.createSession(
            course: fixture.course,
            directory: fixture.audioDirectory
        )

        let url = fixture.audioDirectory.appendingPathComponent(
            LocalRecordingSessionStore.manifestFileName
        )
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(manifest.courseID == fixture.course.id)
        #expect(manifest.course == fixture.course)
        #expect(manifest.finalizationState == .recording)
        #expect(manifest.segments.isEmpty)
    }

    @Test func finalizedSegmentIsAddedWithRelativePath() throws {
        let fixture = try Fixture()
        let manifest = try fixture.store.createSession(course: fixture.course, directory: fixture.audioDirectory)
        let startedAt = Date(timeIntervalSince1970: 100)
        let stored = try fixture.store.beginSegment(
            sessionID: manifest.sessionID,
            in: fixture.audioDirectory,
            relativePath: "segment-0001.m4a",
            sequence: 1,
            startedAt: startedAt
        )
        let audioURL = fixture.audioDirectory.appendingPathComponent(stored.relativePath)
        try Data([1, 2, 3]).write(to: audioURL)
        try fixture.store.finalizeSegment(
            sessionID: manifest.sessionID,
            in: fixture.audioDirectory,
            segment: RecordingSegment(
                id: stored.id,
                courseID: fixture.course.id,
                sequence: 1,
                fileURL: audioURL,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(12),
                byteCount: 3
            ),
            nextSessionState: .paused
        )

        let restored = try #require(fixture.store.recoverableSessions().first)
        #expect(restored.manifest.segments.count == 1)
        #expect(restored.manifest.segments[0].relativePath == "segment-0001.m4a")
        #expect(restored.manifest.segments[0].state == .finalized)
        #expect(restored.recordingSegments[0].fileURL == audioURL)
    }

    @Test func segmentsRemainOrderedAcrossPausesAndResumes() throws {
        let fixture = try Fixture()
        let manifest = try fixture.store.createSession(course: fixture.course, directory: fixture.audioDirectory)
        try fixture.addFinalizedSegment(manifest, sequence: 2)
        try fixture.addFinalizedSegment(manifest, sequence: 1)

        let restored = try #require(fixture.store.recoverableSessions().first)
        #expect(restored.recordingSegments.map(\.sequence) == [1, 2])
        #expect(restored.manifest.segments.map(\.sequence) == [1, 2])
    }

    @Test func stoppedSessionIsPersisted() throws {
        let fixture = try Fixture()
        let manifest = try fixture.store.createSession(course: fixture.course, directory: fixture.audioDirectory)
        try fixture.store.finishSession(sessionID: manifest.sessionID, in: fixture.audioDirectory)

        let restored = try #require(fixture.store.recoverableSessions().first)
        #expect(restored.manifest.finalizationState == .stopped)
    }

    @Test func sessionRestoresAfterStoreIsReopened() throws {
        let fixture = try Fixture()
        let manifest = try fixture.store.createSession(course: fixture.course, directory: fixture.audioDirectory)
        try fixture.addFinalizedSegment(manifest, sequence: 1)
        try fixture.store.finishSession(sessionID: manifest.sessionID, in: fixture.audioDirectory)

        let reopened = try LocalRecordingSessionStore(rootDirectory: fixture.rootDirectory)
        let restored = try #require(reopened.recoverableSessions().first)
        #expect(restored.manifest.courseID == fixture.course.id)
        #expect(restored.recordingSegments.count == 1)
        #expect(restored.manifest.finalizationState == .stopped)
    }

    @Test func partiallyValidManifestKeepsValidSegmentsAndReportsProblem() throws {
        let fixture = try Fixture()
        let manifest = try fixture.store.createSession(course: fixture.course, directory: fixture.audioDirectory)
        let stored = try fixture.store.beginSegment(
            sessionID: manifest.sessionID,
            in: fixture.audioDirectory,
            relativePath: "segment-0001.m4a",
            sequence: 1,
            startedAt: Date(timeIntervalSince1970: 100)
        )
        try Data([1]).write(to: fixture.audioDirectory.appendingPathComponent(stored.relativePath))

        let manifestURL = fixture.audioDirectory.appendingPathComponent(LocalRecordingSessionStore.manifestFileName)
        var raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let validSegment = try #require((raw["segments"] as? [Any])?.first)
        raw["segments"] = [validSegment, ["sequence": 2]]
        try JSONSerialization.data(withJSONObject: raw).write(to: manifestURL, options: .atomic)

        let restored = try #require(fixture.store.recoverableSessions().first)
        #expect(restored.recordingSegments.map(\.sequence) == [1])
        #expect(restored.issues.contains(.malformedSegment(relativePath: nil)))
    }

    @Test func missingAudioFileIsRetainedInManifestAndReported() throws {
        let fixture = try Fixture()
        let manifest = try fixture.store.createSession(course: fixture.course, directory: fixture.audioDirectory)
        _ = try fixture.store.beginSegment(
            sessionID: manifest.sessionID,
            in: fixture.audioDirectory,
            relativePath: "segment-0001.m4a",
            sequence: 1,
            startedAt: Date()
        )

        let restored = try #require(fixture.store.recoverableSessions().first)
        #expect(restored.manifest.segments.count == 1)
        #expect(restored.recordingSegments.isEmpty)
        #expect(restored.issues.contains(.missingAudioFile(relativePath: "segment-0001.m4a")))
    }

    @Test func previousUnfinishedSessionIsRecovered() throws {
        let fixture = try Fixture()
        let manifest = try fixture.store.createSession(course: fixture.course, directory: fixture.audioDirectory)
        let stored = try fixture.store.beginSegment(
            sessionID: manifest.sessionID,
            in: fixture.audioDirectory,
            relativePath: "segment-0001.m4a",
            sequence: 1,
            startedAt: Date()
        )
        try Data([1, 2]).write(to: fixture.audioDirectory.appendingPathComponent(stored.relativePath))

        let reopened = try LocalRecordingSessionStore(rootDirectory: fixture.rootDirectory)
        let restored = try #require(reopened.recoverableSessions().first)
        #expect(restored.manifest.finalizationState == .recording)
        #expect(restored.issues.contains(.incompleteSegment(relativePath: "segment-0001.m4a")))
    }

    @Test func transcribedSessionIsNotPresentedForRecovery() throws {
        let fixture = try Fixture()
        let manifest = try fixture.store.createSession(course: fixture.course, directory: fixture.audioDirectory)
        try fixture.store.finishSession(sessionID: manifest.sessionID, in: fixture.audioDirectory)
        let transcriptionURL = fixture.rootDirectory
            .appendingPathComponent(fixture.course.id.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("transcription", isDirectory: true)
            .appendingPathComponent("raw-transcription.json")
        try FileManager.default.createDirectory(
            at: transcriptionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: transcriptionURL)

        #expect(try fixture.store.recoverableSessions().isEmpty)
    }
}

@MainActor
private final class Fixture {
    let rootDirectory: URL
    let audioDirectory: URL
    let course: Course
    let store: LocalRecordingSessionStore

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScribRecordingSessionTests-\(UUID().uuidString)", isDirectory: true)
        audioDirectory = rootDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let teacher = Teacher(name: "Dr Martin", recordingAuthorizationConfirmedAt: Date())
        course = Course(
            semester: .semester1,
            teachingUnit: TeachingUnitCatalog.units(for: .semester1)[0],
            title: "Anatomie",
            teacher: teacher,
            expectedDuration: .oneHour
        )
        store = try LocalRecordingSessionStore(rootDirectory: rootDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func addFinalizedSegment(_ manifest: RecordingSessionManifest, sequence: Int) throws {
        let startedAt = Date(timeIntervalSince1970: TimeInterval(sequence * 100))
        let relativePath = String(format: "segment-%04d.m4a", sequence)
        let stored = try store.beginSegment(
            sessionID: manifest.sessionID,
            in: audioDirectory,
            relativePath: relativePath,
            sequence: sequence,
            startedAt: startedAt
        )
        let audioURL = audioDirectory.appendingPathComponent(relativePath)
        try Data([1, 2]).write(to: audioURL)
        try store.finalizeSegment(
            sessionID: manifest.sessionID,
            in: audioDirectory,
            segment: RecordingSegment(
                id: stored.id,
                courseID: course.id,
                sequence: sequence,
                fileURL: audioURL,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(10),
                byteCount: 2
            ),
            nextSessionState: .paused
        )
    }
}
