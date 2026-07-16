import Foundation

public enum ReleaseArtifactReadError: Error, Sendable, Equatable, LocalizedError {
    case integrityFailure([String])
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .integrityFailure(let issues):
            "Release artifact integrity failed: \(issues.joined(separator: "; "))"
        case .unreadable(let reason):
            "Release artifact could not be read: \(reason)"
        }
    }
}
