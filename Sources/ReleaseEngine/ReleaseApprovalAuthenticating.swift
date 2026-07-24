import CircuiteFoundation
import DesignFlowKernel
import Foundation

public protocol ReleaseApprovalAuthenticating: Sendable {
    func authenticate(
        approval: FlowApprovalRecord,
        runID: String,
        signoffBundle: ArtifactReference,
        evaluatedAt: Date
    ) async throws
}
