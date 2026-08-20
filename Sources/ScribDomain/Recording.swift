import Foundation

public enum AudioRecorderState: String, Codable, Sendable {
    case idle
    case recording
    case paused
    case finished
    case failed
}

public struct RecordingSegment: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let courseID: CourseID
    public let sequence: Int
    public let fileURL: URL
    public let startedAt: Date
    public let endedAt: Date
    public let byteCount: Int64

    public init(
        id: UUID = UUID(),
        courseID: CourseID,
        sequence: Int,
        fileURL: URL,
        startedAt: Date,
        endedAt: Date,
        byteCount: Int64
    ) {
        self.id = id
        self.courseID = courseID
        self.sequence = sequence
        self.fileURL = fileURL
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.byteCount = max(byteCount, 0)
    }

    public var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
    }
}

public struct AudioRecorderSnapshot: Equatable, Sendable {
    public var state: AudioRecorderState
    public var elapsed: TimeInterval
    public var averagePowerDecibels: Float
    public var segments: [RecordingSegment]
    public var activeInputName: String
    public var incidentMessage: String?

    public init(
        state: AudioRecorderState = .idle,
        elapsed: TimeInterval = 0,
        averagePowerDecibels: Float = -80,
        segments: [RecordingSegment] = [],
        activeInputName: String = "Microphone système",
        incidentMessage: String? = nil
    ) {
        self.state = state
        self.elapsed = max(elapsed, 0)
        self.averagePowerDecibels = averagePowerDecibels
        self.segments = segments
        self.activeInputName = activeInputName
        self.incidentMessage = incidentMessage
    }

    public var normalizedLevel: Double {
        let clamped = min(max(Double(averagePowerDecibels), -60), 0)
        return (clamped + 60) / 60
    }
}

public enum AudioStoragePolicy {
    public static let captureSampleRate: Double = 48_000
    public static let captureChannelCount = 1
    public static let targetBitRate: Int64 = 64_000
    public static let safetyMultiplier = 1.25

    public static func requiredBytes(for duration: ExpectedDuration) -> Int64 {
        let payload = Double(targetBitRate) / 8 * duration.timeInterval
        return Int64((payload * safetyMultiplier).rounded(.up))
    }
}
