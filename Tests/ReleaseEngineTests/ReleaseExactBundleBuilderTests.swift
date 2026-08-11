import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore
import DesignFlowKernel
import Foundation
import ReleaseCore
import Testing
import ToolQualification

@Suite("Exact release bundle building")
struct ReleaseExactBundleBuilderTests {
    @Test("owner outputs derive one deterministic exact content inventory")
    func derivesExactInventory() throws {
        let fixture = try Fixture()

        let bundle = try DefaultReleaseExactBundleBuilder().build(fixture.request)

        #expect(Set(bundle.approvalContentIdentities) == Set([
            fixture.approvalRecord.reference.id,
        ]))
        #expect(Set(bundle.qualificationContentIdentities) == Set([
            fixture.qualificationRecord.reference.id,
        ]))
        #expect(Set(bundle.contentIdentities) == Set([
            fixture.plan.reference.id,
            fixture.signoff.reference.id,
            fixture.signoffEvidence.id,
            fixture.approvalRecord.reference.id,
            fixture.qualificationRecord.reference.id,
            fixture.qualificationInput.id,
            fixture.trustEvidence.id,
            fixture.healthEvidence.id,
            fixture.additionalContent.id,
        ]))
        try DefaultReleaseExactBundleValidator().validate(bundle)
    }

    @Test("an inactive retention receipt fails before a bundle is returned")
    func rejectsInactiveRetention() throws {
        let fixture = try Fixture(retentionState: .released)

        #expect(throws: ReleaseExactBundleBuildError.invalidBundle(
            .inactiveRetentionReceipt(fixture.revision)
        )) {
            try DefaultReleaseExactBundleBuilder().build(fixture.request)
        }
    }

    @Test("a non-ready signoff bundle is rejected before inventory construction")
    func rejectsNonReadySignoffBundle() throws {
        let fixture = try Fixture(signoffReleaseReady: false)

        #expect(throws: ReleaseExactBundleBuildError.signoffBundleNotReleaseReady) {
            try DefaultReleaseExactBundleBuilder().build(fixture.request)
        }
    }

    @Test("the signoff reference must bind the exact owner digest")
    func rejectsSignoffReferenceMismatch() throws {
        let fixture = try Fixture(
            referencedDesignDigest: String(repeating: "0", count: 64)
        )

        #expect(throws: ReleaseExactBundleBuildError.signoffReferenceMismatch(
            field: "design digest"
        )) {
            try DefaultReleaseExactBundleBuilder().build(fixture.request)
        }
    }

    @Test("the signoff artifact identity must match canonical owner bytes")
    func rejectsSignoffArtifactIdentityMismatch() throws {
        let fixture = try Fixture(tamperSignoffArtifactIdentity: true)

        #expect(throws: ReleaseExactBundleBuildError.signoffArtifactIdentityMismatch) {
            try DefaultReleaseExactBundleBuilder().build(fixture.request)
        }
    }

    @Test("a rejected approval cannot be retained as release approval content")
    func rejectsRejectedApproval() throws {
        let fixture = try Fixture(approvalVerdict: .rejected)

        #expect(throws: ReleaseExactBundleBuildError.approvalRejected) {
            try DefaultReleaseExactBundleBuilder().build(fixture.request)
        }
    }

    @Test("the approval must bind the exact signoff artifact")
    func rejectsApprovalSignoffMismatch() throws {
        let fixture = try Fixture(approvalBindsSignoff: false)

        #expect(throws: ReleaseExactBundleBuildError
            .approvalSignoffArtifactMismatch) {
            try DefaultReleaseExactBundleBuilder().build(fixture.request)
        }
    }

    private struct Fixture {
        let revision: DesignRevisionReference
        let plan: FlowArtifactBinding
        let approvalRecord: FlowArtifactBinding
        let qualificationRecord: FlowArtifactBinding
        let signoff: ReleaseArtifactBinding
        let signoffEvidence: ArtifactReference
        let qualificationInput: ArtifactReference
        let trustEvidence: ArtifactReference
        let healthEvidence: ArtifactReference
        let additionalContent: ArtifactReference
        let request: ReleaseExactBundleBuildRequest

        init(
            retentionState: DesignRevisionRetentionState = .active,
            signoffReleaseReady: Bool = true,
            referencedDesignDigest: String? = nil,
            tamperSignoffArtifactIdentity: Bool = false,
            approvalVerdict: FlowApprovalRecord.Verdict = .approved,
            approvalBindsSignoff: Bool = true
        ) throws {
            let rootID = try ArtifactRootID(rawValue: "release-test-root")
            let planReference = try Self.artifact(
                digestByte: "1",
                role: .input,
                kind: .request
            )
            signoffEvidence = try Self.artifact(
                digestByte: "3",
                role: .output,
                kind: .evidence
            )
            qualificationInput = try Self.artifact(
                digestByte: "4",
                role: .input,
                kind: .input
            )
            trustEvidence = try Self.artifact(
                digestByte: "5",
                role: .output,
                kind: .evidence
            )
            healthEvidence = try Self.artifact(
                digestByte: "6",
                role: .output,
                kind: .evidence
            )
            additionalContent = try Self.artifact(
                digestByte: "7",
                role: .input,
                kind: .technology
            )
            let approvalRecordReference = try Self.artifact(
                digestByte: "8",
                role: .output,
                kind: .report
            )
            let qualificationRecordReference = try Self.artifact(
                digestByte: "9",
                role: .output,
                kind: .evidence
            )
            let signoffBundle = SignoffBundle(
                bundleID: "signoff-bundle",
                profileID: "digital",
                designDigest: String(repeating: "a", count: 64),
                pdkDigest: String(repeating: "b", count: 64),
                finalLayoutDigest: String(repeating: "c", count: 64),
                axisResults: ReleaseSignoffAxis.allCases.map {
                    SignoffAxisResult(
                        axis: $0,
                        disposition: signoffReleaseReady ? .passed : .blocked,
                        evidenceIDs: ["evidence-\($0.rawValue)"],
                        reason: "passed"
                    )
                },
                waivers: [],
                evidenceRecords: [],
                evidenceArtifacts: [signoffEvidence],
                toolQualificationScopes: [ToolQualificationScope(
                    implementationID: "release-test-tool",
                    toolVersion: "1.0.0",
                    binaryDigest: String(repeating: "1", count: 64),
                    algorithmVersion: "release-test-v1",
                    processProfileID: "test-process",
                    processProfileDigest: String(repeating: "2", count: 64),
                    deckDigest: String(repeating: "3", count: 64),
                    pdkID: "test-process",
                    pdkDigest: String(repeating: "b", count: 64),
                    oracle: ToolOracleQualificationScope(
                        implementationID: "release-test-oracle",
                        version: "1.0.0",
                        binaryDigest: String(repeating: "4", count: 64)
                    )
                )],
                evidenceDigest: String(repeating: "d", count: 64),
                issuedAt: Date(timeIntervalSince1970: 900)
            )
            let signoffReference = if tamperSignoffArtifactIdentity {
                try Self.artifact(
                    digestByte: "0",
                    role: .output,
                    kind: .release
                )
            } else {
                try Self.artifact(
                    content: signoffBundle.canonicalData(),
                    role: .output,
                    kind: .release
                )
            }
            plan = try FlowArtifactBinding(
                logicalID: "release-plan",
                reference: planReference,
                availability: .local(
                    artifactID: planReference.id,
                    rootID: rootID,
                    relativePath: try ArtifactRelativePath(
                        segments: ["release", "plan.json"]
                    )
                )
            )
            approvalRecord = try FlowArtifactBinding(
                logicalID: "release-approval-record",
                reference: approvalRecordReference,
                availability: .local(
                    artifactID: approvalRecordReference.id,
                    rootID: rootID,
                    relativePath: try ArtifactRelativePath(
                        segments: ["release", "approval.json"]
                    )
                )
            )
            qualificationRecord = try FlowArtifactBinding(
                logicalID: "release-qualification-record",
                reference: qualificationRecordReference,
                availability: .local(
                    artifactID: qualificationRecordReference.id,
                    rootID: rootID,
                    relativePath: try ArtifactRelativePath(
                        segments: ["release", "qualification.json"]
                    )
                )
            )
            signoff = try ReleaseArtifactBinding(
                logicalID: "signoff-bundle",
                reference: signoffReference,
                availability: .local(
                    artifactID: signoffReference.id,
                    rootID: rootID,
                    relativePath: try ArtifactRelativePath(
                        segments: ["release", "signoff.json"]
                    )
                )
            )
            let signoffFlowBinding = try FlowArtifactBinding(
                logicalID: "signoff-stage-result",
                reference: signoffReference,
                availability: signoff.availability
            )
            let approval = FlowApprovalRecord(
                runID: "release-run",
                stageID: "release.authorization",
                verdict: approvalVerdict,
                reviewer: "release-reviewer",
                createdAt: Date(timeIntervalSince1970: 1_000),
                evidence: FlowApprovalEvidenceBinding(
                    plan: plan,
                    stageResult: approvalBindsSignoff
                        ? signoffFlowBinding
                        : plan
                )
            )
            let qualificationRequest = ToolQualificationRequest(
                descriptor: ToolDescriptor(
                    toolID: "release-test-tool",
                    displayName: "Release test tool",
                    kind: .reporting,
                    version: "1.0.0",
                    capabilities: [ToolCapability(operationID: "release.authorize")],
                    trustProfile: ToolTrustProfile(
                        level: .smokeChecked,
                        evidence: [ToolEvidence(
                            evidenceID: "trust-evidence",
                            kind: .healthCheck,
                            artifact: trustEvidence,
                            checkedAt: Date(timeIntervalSince1970: 800)
                        )]
                    ),
                    environment: ToolEnvironment(platform: "macOS")
                ),
                requirement: ToolTrustRequirement(
                    kind: .reporting,
                    operationID: "release.authorize",
                    minimumLevel: .smokeChecked
                ),
                health: ToolHealthCheckResult(
                    toolID: "release-test-tool",
                    status: .passed,
                    evidence: [ToolEvidence(
                        evidenceID: "health-evidence",
                        kind: .healthCheck,
                        artifact: healthEvidence,
                        checkedAt: Date(timeIntervalSince1970: 800)
                    )]
                ),
                inputs: [qualificationInput],
                evaluatedAt: Date(timeIntervalSince1970: 1_000)
            )
            let databaseID = try DesignDatabaseID(high: 1, low: 2)
            revision = DesignRevisionReference(
                databaseID: databaseID,
                revisionID: DesignRevisionID(high: 3, low: 4)
            )
            let receipt = DesignRevisionRetentionReceipt(
                operation: DesignDatabaseOperationReference(
                    databaseID: databaseID,
                    authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
                        high: 5,
                        low: 6
                    ),
                    operationID: try DesignDatabaseOperationID(
                        rawValue: "release-retention"
                    )
                ),
                claimID: try DesignRevisionRetentionID(rawValue: "release"),
                revision: revision,
                generation: 1,
                reachabilityGeneration: 1,
                state: retentionState,
                outcomeDigest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "e", count: 64)
                )
            )
            request = ReleaseExactBundleBuildRequest(
                databaseRevisions: [ReleaseDatabaseRevisionBinding(
                    databaseRole: "design",
                    revision: revision
                )],
                semanticDependencyGraphDigest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "f", count: 64)
                ),
                signoffBundle: signoffBundle,
                signoffBundleReference: SignoffBundleReference(
                    artifact: signoff,
                    designDigest: referencedDesignDigest ?? signoffBundle.designDigest,
                    pdkDigest: signoffBundle.pdkDigest,
                    finalLayoutDigest: signoffBundle.finalLayoutDigest
                ),
                approval: approval,
                approvalArtifacts: [approvalRecord],
                toolQualificationRequests: [qualificationRequest],
                qualificationRecordArtifacts: [qualificationRecord],
                additionalContentIdentities: [additionalContent.id],
                retentionReceipts: [receipt]
            )
        }

        private static func artifact(
            digestByte: String,
            role: ArtifactRole,
            kind: ArtifactKind
        ) throws -> ArtifactReference {
            try ArtifactReference(
                digest: ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: digestByte, count: 64)
                ),
                byteCount: 64,
                descriptor: ArtifactDescriptor(
                    role: role,
                    kind: kind,
                    format: .json
                )
            )
        }

        private static func artifact(
            content: Data,
            role: ArtifactRole,
            kind: ArtifactKind
        ) throws -> ArtifactReference {
            try ArtifactReference(
                digest: SHA256ContentDigester().digest(data: content),
                byteCount: UInt64(content.count),
                descriptor: ArtifactDescriptor(
                    role: role,
                    kind: kind,
                    format: .json
                )
            )
        }
    }
}
