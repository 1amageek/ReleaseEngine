import DesignFlowKernel
import Foundation
import ReleaseCore
import ToolQualification

public struct ReleaseAuthorizationRequest: Sendable, Hashable, Codable {
    public let runID: String
    public let stageID: String
    public let signoffBundle: SignoffBundleReference
    public let approval: FlowApprovalRecord
    public let toolTrustDecisions: [ToolTrustDecision]
    public let toolQualificationRequests: [ToolQualificationRequest]
    public let requiredToolIDs: [String]
    public let evaluatedAt: Date

    public init(
        runID: String,
        stageID: String,
        signoffBundle: SignoffBundleReference,
        approval: FlowApprovalRecord,
        toolTrustDecisions: [ToolTrustDecision],
        toolQualificationRequests: [ToolQualificationRequest],
        requiredToolIDs: [String],
        evaluatedAt: Date
    ) {
        self.runID = runID
        self.stageID = stageID
        self.signoffBundle = signoffBundle
        self.approval = approval
        self.toolTrustDecisions = toolTrustDecisions
        self.toolQualificationRequests = toolQualificationRequests
        self.requiredToolIDs = requiredToolIDs
        self.evaluatedAt = evaluatedAt
    }
}
