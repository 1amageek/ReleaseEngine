import Foundation

/// Lifecycle status for a release-domain execution result.
///
/// This status is intentionally owned by ReleaseCore. It is not a universal
/// engine envelope status; each release domain result carries the status
/// alongside its own payload.
public enum ReleaseExecutionStatus: String, Sendable, Hashable, Codable {
    case completed
    case failed
    case blocked
    case cancelled
}
