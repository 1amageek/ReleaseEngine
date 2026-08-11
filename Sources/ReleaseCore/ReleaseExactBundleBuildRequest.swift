import CircuiteFoundation
import DesignDatabaseCore
import DesignFlowKernel
import ToolQualification

public struct ReleaseExactBundleBuildRequest: Sendable, Hashable {
    public let databaseRevisions: [ReleaseDatabaseRevisionBinding]
    public let semanticDependencyGraphDigest: ContentDigest
    public let signoffBundle: SignoffBundle
    public let signoffBundleReference: SignoffBundleReference
    public let approval: FlowApprovalRecord
    public let approvalArtifacts: [FlowArtifactBinding]
    public let toolQualificationRequests: [ToolQualificationRequest]
    public let qualificationRecordArtifacts: [FlowArtifactBinding]
    public let additionalContentIdentities: [ArtifactID]
    public let retentionReceipts: [DesignRevisionRetentionReceipt]

    public init(
        databaseRevisions: [ReleaseDatabaseRevisionBinding],
        semanticDependencyGraphDigest: ContentDigest,
        signoffBundle: SignoffBundle,
        signoffBundleReference: SignoffBundleReference,
        approval: FlowApprovalRecord,
        approvalArtifacts: [FlowArtifactBinding],
        toolQualificationRequests: [ToolQualificationRequest],
        qualificationRecordArtifacts: [FlowArtifactBinding],
        additionalContentIdentities: [ArtifactID] = [],
        retentionReceipts: [DesignRevisionRetentionReceipt]
    ) {
        self.databaseRevisions = databaseRevisions
        self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
        self.signoffBundle = signoffBundle
        self.signoffBundleReference = signoffBundleReference
        self.approval = approval
        self.approvalArtifacts = approvalArtifacts
        self.toolQualificationRequests = toolQualificationRequests
        self.qualificationRecordArtifacts = qualificationRecordArtifacts
        self.additionalContentIdentities = additionalContentIdentities
        self.retentionReceipts = retentionReceipts
    }
}
