import Foundation
import CircuiteFoundation

public protocol ReleaseArtifactPersisting: Sendable {
    /// Creates an immutable artifact. Implementations must serialize writers for the same
    /// location and reject an existing artifact instead of replacing it.
    func persist(
        _ request: ReleaseArtifactPersistenceRequest,
        relativeTo projectRoot: URL
    ) async throws -> ArtifactReference

    /// Reloads the exact persisted bytes for post-write verification.
    func load(
        _ artifact: ArtifactReference,
        relativeTo projectRoot: URL
    ) async throws -> Data
}
