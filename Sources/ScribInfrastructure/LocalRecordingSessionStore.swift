import Foundation
import ScribApplication
import ScribDomain

public enum LocalRecordingSessionStoreError: LocalizedError {
    case sessionAlreadyExists(URL)
    case missingSession(UUID)
    case invalidRelativePath(String)
    case inconsistentCourseID

    public var errorDescription: String? {
        switch self {
        case let .sessionAlreadyExists(url):
            "Une session d'enregistrement existe déjà dans \(url.path)."
        case let .missingSession(id):
            "La session d'enregistrement \(id.uuidString) est introuvable."
        case let .invalidRelativePath(path):
            "Le chemin relatif de segment est invalide : \(path)."
        case .inconsistentCourseID:
            "Le manifeste ne correspond pas au cours attendu."
        }
    }
}

/// Persists the smallest durable unit needed to recover locally recorded audio.
/// Each manifest lives next to its audio, while discovery starts from `Courses`.
@MainActor
public final class LocalRecordingSessionStore: RecordingSessionStoring {
    public static let manifestFileName = "recording-session.json"

    private let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootDirectory = support
                .appendingPathComponent("Scrib", isDirectory: true)
                .appendingPathComponent("Courses", isDirectory: true)
        }
        try fileManager.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    public func createSession(course: Course, directory: URL) throws -> RecordingSessionManifest {
        let url = manifestURL(in: directory)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw LocalRecordingSessionStoreError.sessionAlreadyExists(url)
        }
        let manifest = RecordingSessionManifest(course: course)
        try persist(manifest, to: url)
        return manifest
    }

    public func beginSegment(
        sessionID: UUID,
        in directory: URL,
        relativePath: String,
        sequence: Int,
        startedAt: Date
    ) throws -> RecordingSessionManifest.Segment {
        guard isSafeRelativePath(relativePath) else {
            throw LocalRecordingSessionStoreError.invalidRelativePath(relativePath)
        }
        var manifest = try manifest(sessionID: sessionID, in: directory)
        let segment = RecordingSessionManifest.Segment(
            relativePath: relativePath,
            sequence: sequence,
            state: .recording,
            createdAt: startedAt
        )
        manifest.segments.append(segment)
        manifest.segments.sort { $0.sequence < $1.sequence }
        manifest.finalizationState = .recording
        manifest.updatedAt = Date()
        try persist(manifest, to: manifestURL(in: directory))
        return segment
    }

    public func finalizeSegment(
        sessionID: UUID,
        in directory: URL,
        segment: RecordingSegment,
        nextSessionState: RecordingSessionFinalizationState
    ) throws {
        var manifest = try manifest(sessionID: sessionID, in: directory)
        guard let index = manifest.segments.firstIndex(where: { $0.sequence == segment.sequence }) else {
            throw LocalRecordingSessionStoreError.missingSession(sessionID)
        }
        var stored = manifest.segments[index]
        stored.state = .finalized
        stored.finalizedAt = segment.endedAt
        stored.durationSeconds = segment.duration
        stored.byteCount = segment.byteCount
        manifest.segments[index] = stored
        manifest.finalizationState = nextSessionState
        manifest.updatedAt = Date()
        try persist(manifest, to: manifestURL(in: directory))
    }

    public func failActiveSegment(
        sessionID: UUID,
        in directory: URL,
        relativePath: String,
        endedAt: Date,
        byteCount: Int64
    ) throws {
        var manifest = try manifest(sessionID: sessionID, in: directory)
        guard let index = manifest.segments.lastIndex(where: { $0.relativePath == relativePath }) else {
            throw LocalRecordingSessionStoreError.missingSession(sessionID)
        }
        manifest.segments[index].state = .failed
        manifest.segments[index].finalizedAt = endedAt
        manifest.segments[index].durationSeconds = max(
            endedAt.timeIntervalSince(manifest.segments[index].createdAt),
            0
        )
        manifest.segments[index].byteCount = max(byteCount, 0)
        manifest.finalizationState = .failed
        manifest.updatedAt = Date()
        try persist(manifest, to: manifestURL(in: directory))
    }

    public func finishSession(sessionID: UUID, in directory: URL) throws {
        var manifest = try manifest(sessionID: sessionID, in: directory)
        manifest.finalizationState = .stopped
        manifest.updatedAt = Date()
        try persist(manifest, to: manifestURL(in: directory))
    }

    public func recoverableSessions() throws -> [RecoveredRecordingSession] {
        try discoveredSessions(includeTranscribed: false)
    }

    public func recordingSession(for courseID: CourseID) throws -> RecoveredRecordingSession? {
        try discoveredSessions(includeTranscribed: true)
            .filter { $0.manifest.courseID == courseID }
            .max { $0.manifest.updatedAt < $1.manifest.updatedAt }
    }

    private func discoveredSessions(includeTranscribed: Bool) throws -> [RecoveredRecordingSession] {
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var recovered: [RecoveredRecordingSession] = []
        for case let url as URL in enumerator where url.lastPathComponent == Self.manifestFileName {
            guard let decoded = try? decodeTolerantly(from: url) else { continue }
            let manifest = decoded.manifest
            guard manifest.courseID == manifest.course.id else { continue }

            // A successful local transcription is already the durable successor of this session.
            guard includeTranscribed || !isTranscribed(courseID: manifest.courseID) else { continue }

            let directory = url.deletingLastPathComponent()
            var issues = decoded.issues
            var segments: [RecordingSegment] = []
            var seenIDs = Set<UUID>()
            var seenSequences = Set<Int>()
            for stored in manifest.segments.sorted(by: { $0.sequence < $1.sequence }) {
                guard seenIDs.insert(stored.id).inserted,
                      seenSequences.insert(stored.sequence).inserted else {
                    issues.append(.duplicateSegment(sequence: stored.sequence))
                    continue
                }
                guard isSafeRelativePath(stored.relativePath) else {
                    issues.append(.malformedSegment(relativePath: stored.relativePath))
                    continue
                }
                let audioURL = directory.appendingPathComponent(stored.relativePath)
                guard fileManager.fileExists(atPath: audioURL.path) else {
                    issues.append(.missingAudioFile(relativePath: stored.relativePath))
                    continue
                }

                if stored.state != .finalized {
                    issues.append(.incompleteSegment(relativePath: stored.relativePath))
                }
                let attributes = try? fileManager.attributesOfItem(atPath: audioURL.path)
                let endedAt = stored.finalizedAt
                    ?? stored.durationSeconds.map { stored.createdAt.addingTimeInterval($0) }
                    ?? (attributes?[.modificationDate] as? Date)
                    ?? stored.createdAt
                let byteCount = stored.byteCount
                    ?? (attributes?[.size] as? NSNumber)?.int64Value
                    ?? 0
                segments.append(
                    RecordingSegment(
                        id: stored.id,
                        courseID: manifest.courseID,
                        sequence: stored.sequence,
                        fileURL: audioURL,
                        startedAt: stored.createdAt,
                        endedAt: endedAt,
                        byteCount: byteCount
                    )
                )
            }
            recovered.append(
                RecoveredRecordingSession(
                    manifest: manifest,
                    recordingSegments: segments,
                    issues: issues
                )
            )
        }
        return recovered.sorted { $0.manifest.updatedAt > $1.manifest.updatedAt }
    }

    private func manifest(sessionID: UUID, in directory: URL) throws -> RecordingSessionManifest {
        let url = manifestURL(in: directory)
        guard fileManager.fileExists(atPath: url.path) else {
            throw LocalRecordingSessionStoreError.missingSession(sessionID)
        }
        let decoded = try decodeTolerantly(from: url).manifest
        guard decoded.sessionID == sessionID else {
            throw LocalRecordingSessionStoreError.missingSession(sessionID)
        }
        guard decoded.courseID == decoded.course.id else {
            throw LocalRecordingSessionStoreError.inconsistentCourseID
        }
        return decoded
    }

    private func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent(Self.manifestFileName)
    }

    private func persist(_ manifest: RecordingSessionManifest, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private func isTranscribed(courseID: CourseID) -> Bool {
        let transcriptionURL = rootDirectory
            .appendingPathComponent(courseID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("transcription", isDirectory: true)
            .appendingPathComponent("raw-transcription.json")
        return fileManager.fileExists(atPath: transcriptionURL.path)
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        return !path.isEmpty
            && !path.hasPrefix("/")
            && !path.contains(":")
            && !path.split(separator: "/").contains("..")
            && !path.contains("\\")
    }

    private func decodeTolerantly(from url: URL) throws -> DecodedManifest {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let manifest = try? decoder.decode(RecordingSessionManifest.self, from: data) {
            return DecodedManifest(manifest: manifest, issues: [])
        }

        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSegments = object["segments"] as? [Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var validSegments: [Any] = []
        var issues: [RecordingSessionRecoveryIssue] = []
        for rawSegment in rawSegments {
            guard JSONSerialization.isValidJSONObject(rawSegment),
                  let segmentData = try? JSONSerialization.data(withJSONObject: rawSegment),
                  let segment = try? decoder.decode(RecordingSessionManifest.Segment.self, from: segmentData) else {
                let path = (rawSegment as? [String: Any])?["relativePath"] as? String
                issues.append(.malformedSegment(relativePath: path))
                continue
            }
            _ = segment
            validSegments.append(rawSegment)
        }
        object["segments"] = validSegments
        let repairedData = try JSONSerialization.data(withJSONObject: object)
        let manifest = try decoder.decode(RecordingSessionManifest.self, from: repairedData)
        return DecodedManifest(manifest: manifest, issues: issues)
    }

    private struct DecodedManifest {
        var manifest: RecordingSessionManifest
        var issues: [RecordingSessionRecoveryIssue]
    }
}
