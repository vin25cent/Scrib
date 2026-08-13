public enum InfrastructureStatus: Equatable, Sendable {
    case notConfigured
    case ready
    case unavailable(reason: String)
}

/// Point d'ancrage du module. Les adaptateurs concrets seront ajoutés pendant
/// les prototypes audio, transcription, cloud, DOCX et stockage.
public struct InfrastructureRegistry: Sendable {
    public var status: InfrastructureStatus

    public init(status: InfrastructureStatus = .notConfigured) {
        self.status = status
    }
}
