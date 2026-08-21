import Foundation
import ScribApplication
import ScribDomain

public enum LocalTranscriptionStoreError: LocalizedError, Sendable {
    case noStoredTranscription(CourseID)
    case noReplacementCandidate(CourseID)

    public var errorDescription: String? {
        switch self {
        case .noStoredTranscription:
            "La transcription locale à mettre à jour est introuvable."
        case .noReplacementCandidate:
            "La nouvelle transcription à confirmer est introuvable."
        }
    }
}

public actor LocalTranscriptionStore: LocalTranscriptionStoring {
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

    public func save(_ transcription: StoredLocalTranscription) throws {
        let destination = fileURL(for: transcription.course.id)
        try write(transcription, to: destination)
    }

    public func saveReplacementCandidate(_ transcription: StoredLocalTranscription) throws {
        try write(transcription, to: candidateFileURL(for: transcription.course.id))
    }

    public func replacementCandidate(for courseID: CourseID) throws -> StoredLocalTranscription? {
        let url = candidateFileURL(for: courseID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decode(from: url)
    }

    public func promoteReplacementCandidate(
        for courseID: CourseID
    ) throws -> StoredLocalTranscription {
        guard let candidate = try replacementCandidate(for: courseID) else {
            throw LocalTranscriptionStoreError.noReplacementCandidate(courseID)
        }
        try save(candidate)
        try discardReplacementCandidate(for: courseID)
        return candidate
    }

    public func discardReplacementCandidate(for courseID: CourseID) throws {
        let url = candidateFileURL(for: courseID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func transcription(for courseID: CourseID) throws -> StoredLocalTranscription? {
        let url = fileURL(for: courseID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decode(from: url)
    }

    private func write(_ transcription: StoredLocalTranscription, to destination: URL) throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcription)
        try data.write(to: destination, options: .atomic)
    }

    public func updateDraft(_ draft: TranscriptDraft) throws {
        let source = fileURL(for: draft.courseID)
        guard fileManager.fileExists(atPath: source.path) else {
            throw LocalTranscriptionStoreError.noStoredTranscription(draft.courseID)
        }
        var stored = try decode(from: source)
        stored.draft = draft
        try save(stored)
    }

    public func latest() throws -> StoredLocalTranscription? {
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [(url: URL, date: Date)] = []
        for case let url as URL in enumerator where url.lastPathComponent == "raw-transcription.json" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            candidates.append((url, date))
        }
        for candidate in candidates.sorted(by: { $0.date > $1.date }) {
            if let stored = try? decode(from: candidate.url) {
                return stored
            }
        }
        return nil
    }

    private func fileURL(for courseID: CourseID) -> URL {
        rootDirectory
            .appendingPathComponent(courseID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("transcription", isDirectory: true)
            .appendingPathComponent("raw-transcription.json")
    }

    private func candidateFileURL(for courseID: CourseID) -> URL {
        rootDirectory
            .appendingPathComponent(courseID.rawValue.uuidString, isDirectory: true)
            .appendingPathComponent("transcription", isDirectory: true)
            .appendingPathComponent("replacement-candidate.json")
    }

    private func decode(from url: URL) throws -> StoredLocalTranscription {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredLocalTranscription.self, from: Data(contentsOf: url))
    }
}
