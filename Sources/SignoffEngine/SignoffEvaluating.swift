import Foundation
import XcircuitePackage
import ReleaseCore

public protocol SignoffEvaluating: Sendable {
    func execute(
        _ request: SignoffRequest
    ) async throws -> XcircuiteEngineResultEnvelope<SignoffPayload>
}
