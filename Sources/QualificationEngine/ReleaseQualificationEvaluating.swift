import Foundation
import XcircuitePackage

public protocol ReleaseQualificationEvaluating: Sendable {
    func execute(
        _ request: ReleaseQualificationRequest
    ) async throws -> XcircuiteEngineResultEnvelope<ReleaseQualificationPayload>
}
