import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore
import ToolQualification

public struct ReleaseAuthorizationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 5

    public let schemaVersion: Int
    public let runID: String
    public let stageID: String
    public let signoffBundle: SignoffBundleReference
    public let exactReleaseBundle: ReleaseExactBundle
    public let approval: FlowApprovalRecord
    public let approvalArtifacts: [FlowArtifactBinding]
    public let qualificationRecordArtifacts: [FlowArtifactBinding]
    public let artifactBindings: [ReleaseArtifactBinding]
    public let additionalContentIdentities: [ArtifactID]
    public let toolTrustDecisions: [ToolTrustDecision]
    public let toolQualificationRequests: [ToolQualificationRequest]
    public let requiredToolIDs: [String]
    public let evaluatedAt: Date
    public let projectRoot: String?

    public init(
        runID: String,
        stageID: String,
        signoffBundle: SignoffBundleReference,
        exactReleaseBundle: ReleaseExactBundle,
        approval: FlowApprovalRecord,
        approvalArtifacts: [FlowArtifactBinding],
        qualificationRecordArtifacts: [FlowArtifactBinding],
        artifactBindings: [ReleaseArtifactBinding],
        additionalContentIdentities: [ArtifactID] = [],
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
        self.exactReleaseBundle = exactReleaseBundle
        self.approval = approval
        self.approvalArtifacts = approvalArtifacts
        self.qualificationRecordArtifacts = qualificationRecordArtifacts
        self.artifactBindings = artifactBindings
        self.additionalContentIdentities = additionalContentIdentities.sorted {
            $0.description < $1.description
        }
        self.toolTrustDecisions = toolTrustDecisions
        self.toolQualificationRequests = toolQualificationRequests
        self.requiredToolIDs = requiredToolIDs
        self.evaluatedAt = evaluatedAt
        self.projectRoot = projectRoot
    }
}
