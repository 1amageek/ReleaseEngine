import Foundation

public protocol ReleaseArtifactReading: Sendable {
    func load(
        _ artifact: ReleaseArtifactBinding,
        relativeTo projectRoot: URL
    ) async throws -> Data
}
