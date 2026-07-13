import Foundation

/// Execution state of a release-profile stage at the Foundation boundary.
public enum FoundationReleaseProfileStageStatus: String, Sendable, Hashable, Codable {
    case completed
    case failed
    case blocked
    case cancelled
}
