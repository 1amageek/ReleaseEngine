import Foundation
import ReleaseCore
import CircuiteFoundation

public protocol LayoutXORComparing: Sendable {
    func compare(
        source: ArtifactReference,
        streamed: ArtifactReference,
        pdkDigest: String,
        projectRoot: URL?
    ) async -> LayoutXORResult
}
