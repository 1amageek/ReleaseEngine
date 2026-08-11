import Foundation
import ReleaseCore
import CircuiteFoundation

public protocol LayoutXORComparing: Sendable {
    func compare(
        source: ReleaseArtifactBinding,
        streamed: ReleaseArtifactBinding,
        pdkDigest: String,
        projectRoot: URL?
    ) async -> LayoutXORResult
}
