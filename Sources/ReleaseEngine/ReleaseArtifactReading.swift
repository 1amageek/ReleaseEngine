import CircuiteFoundation
import Foundation

public protocol ReleaseArtifactReading: Sendable {
    func verifiedData(for reference: ArtifactReference) async throws -> Data
}
