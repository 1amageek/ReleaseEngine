import DesignFlowKernel
import Foundation
import ReleaseCore
import ToolQualification

public struct ReleaseAuthorizationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: String
    public let stageID: String
    public let signoffBundle: SignoffBundleReference
    public let approval: FlowApprovalRecord
    public let toolTrustDecisions: [ToolTrustDecision]
    public let toolQualificationRequests: [ToolQualificationRequest]
    public let requiredToolIDs: [String]
    public let evaluatedAt: Date
    public let projectRoot: String?

    public init(
        runID: String,
        stageID: String,
        signoffBundle: SignoffBundleReference,
        approval: FlowApprovalRecord,
        toolTrustDecisions: [ToolTrustDecision],
        toolQualificationRequests: [ToolQualificationRequest],
        requiredToolIDs: [String],
        evaluatedAt: Date,
        projectRoot: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.stageID = stageID
        self.signoffBundle = signoffBundle
        self.approval = approval
        self.toolTrustDecisions = toolTrustDecisions
        self.toolQualificationRequests = toolQualificationRequests
        self.requiredToolIDs = requiredToolIDs
        self.evaluatedAt = evaluatedAt
        self.projectRoot = projectRoot
    }
}
