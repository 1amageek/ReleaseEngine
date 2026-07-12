import Foundation
import XcircuitePackage
import ReleaseCore
import PhysicalDesignCore
import PDKCore

public protocol TapeoutPackaging: Sendable {
    func execute(
        _ request: TapeoutRequest
    ) async throws -> XcircuiteEngineResultEnvelope<TapeoutPayload>
}
