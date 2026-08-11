import Foundation
import CircuiteFoundation

public protocol ReleaseArtifactPersisting: ReleaseArtifactReading, Sendable {
    /// Creates an immutable artifact. Implementations must serialize writers for the same
    /// location and reject an existing artifact instead of replacing it.
    func persist(
        _ request: ReleaseArtifactPersistenceRequest,
        relativeTo projectRoot: URL
    ) async throws -> ReleaseArtifactBinding

}
