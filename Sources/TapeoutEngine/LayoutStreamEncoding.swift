import Foundation
import PhysicalDesignCore
import CircuiteFoundation

public protocol LayoutStreamEncoding: Sendable {
    func encode(
        _ source: PhysicalDesignReference,
        format: ArtifactFormat,
        relativeTo projectRoot: URL
    ) async throws -> Data
}
