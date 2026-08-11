import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore

public protocol ReleaseAuthorizationArtifactReading: Sendable {
    func verifiedData(for binding: ReleaseArtifactBinding) async throws -> Data
    func verifiedData(for binding: FlowArtifactBinding) async throws -> Data
}
