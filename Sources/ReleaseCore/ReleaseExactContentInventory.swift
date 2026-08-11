import CircuiteFoundation
import DesignFlowKernel
import ToolQualification

public struct ReleaseExactContentInventory: Sendable, Hashable {
    public let contentIdentities: [ArtifactID]
    public let approvalContentIdentities: [ArtifactID]
    public let qualificationContentIdentities: [ArtifactID]

    public init(request: ReleaseExactBundleBuildRequest) {
        self.init(
            signoffBundle: request.signoffBundle,
            signoffBundleReference: request.signoffBundleReference,
            approval: request.approval,
            approvalArtifacts: request.approvalArtifacts,
            toolQualificationRequests: request.toolQualificationRequests,
            qualificationRecordArtifacts: request.qualificationRecordArtifacts,
            additionalContentIdentities: request.additionalContentIdentities
        )
    }

    public init(
        signoffBundle: SignoffBundle,
        signoffBundleReference: SignoffBundleReference,
        approval: FlowApprovalRecord,
        approvalArtifacts: [FlowArtifactBinding],
        toolQualificationRequests: [ToolQualificationRequest],
        qualificationRecordArtifacts: [FlowArtifactBinding],
        additionalContentIdentities: [ArtifactID] = []
    ) {
        let approvalEvidenceArtifacts = [
            approval.evidence.plan.reference,
            approval.evidence.stageResult.reference,
        ]
        let qualificationEvidenceArtifacts = Self.qualificationArtifacts(
            signoffBundle: signoffBundle,
            requests: toolQualificationRequests
        )
        let signoffArtifacts = [signoffBundleReference.artifact.reference]
            + signoffBundle.evidenceArtifacts
            + signoffBundle.evidenceRecords.map(\.artifact)
            + signoffBundle.evidenceRecords.flatMap(\.inputArtifacts)
            + signoffBundle.evidenceRecords.flatMap(
                \.executionProvenance.inputs
            )

        approvalContentIdentities = Self.sortedUniqueIDs(
            approvalArtifacts.map(\.reference.id)
        )
        qualificationContentIdentities = Self.sortedUniqueIDs(
            qualificationRecordArtifacts.map(\.reference.id)
        )
        contentIdentities = Self.sortedUniqueIDs(
            signoffArtifacts.map(\.id)
                + approvalContentIdentities
                + approvalEvidenceArtifacts.map(\.id)
                + qualificationContentIdentities
                + qualificationEvidenceArtifacts.map(\.id)
                + additionalContentIdentities
        )
    }

    private static func qualificationArtifacts(
        signoffBundle: SignoffBundle,
        requests: [ToolQualificationRequest]
    ) -> [ArtifactReference] {
        let retainedBySignoff = signoffBundle.evidenceRecords.flatMap {
            processQualificationArtifacts($0.processQualification)
        }
        let retainedByRequests = requests.flatMap { request in
            let processArtifacts = request.descriptor.trustProfile
                .processQualification
                .map(processQualificationArtifacts) ?? []
            return request.inputs
                + request.descriptor.trustProfile.evidence.compactMap(\.artifact)
                + (request.health?.evidence.compactMap(\.artifact) ?? [])
                + processArtifacts
        }
        return retainedBySignoff + retainedByRequests
    }

    private static func processQualificationArtifacts(
        _ qualification: ToolProcessQualificationEvidence
    ) -> [ArtifactReference] {
        qualification.identityArtifacts.all
            + qualification.evidenceArtifacts
            + qualification.inputArtifacts
            + qualification.outputArtifacts
    }

    private static func sortedUniqueIDs(_ identities: [ArtifactID]) -> [ArtifactID] {
        Array(Set(identities)).sorted { $0.description < $1.description }
    }
}
