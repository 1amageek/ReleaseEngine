import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseEngine
import Testing

@Suite("Local release approval authentication")
struct AttestedReleaseApprovalAuthenticatorTests {
    @Test("canonical human approval action authenticates the reviewed signoff bundle")
    func authenticatesCanonicalLedgerDecision() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        try await fixture.authenticator.authenticate(
            approval: fixture.approval,
            runID: fixture.runID,
            signoffBundle: fixture.bundle,
            evaluatedAt: fixture.evaluatedAt
        )
    }

    @Test("request-only approval cannot substitute for the canonical decision")
    func rejectsForgedRequestApproval() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let forged = FlowApprovalRecord(
            runID: fixture.approval.runID,
            stageID: fixture.approval.stageID,
            verdict: .approved,
            reviewer: "forged-reviewer",
            reviewerKind: .human,
            note: fixture.approval.note,
            createdAt: fixture.approval.createdAt,
            evidence: fixture.approval.evidence
        )

        await #expect(throws: ReleaseApprovalAuthenticationError.approvalNotRetained) {
            try await fixture.authenticator.authenticate(
                approval: forged,
                runID: fixture.runID,
                signoffBundle: fixture.bundle,
                evaluatedAt: fixture.evaluatedAt
            )
        }
    }

    private struct Fixture {
        let root: URL
        let runID = "release-authentication-run"
        let evaluatedAt = Date(timeIntervalSince1970: 1_900_000_100)
        let bundle: ArtifactReference
        let approval: FlowApprovalRecord
        let authenticator: AttestedReleaseApprovalAuthenticator

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(
                path: "AttestedReleaseApprovalAuthenticatorTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            let stageID = "release.signoff"
            bundle = try Self.write(
                Data("canonical-signoff-bundle".utf8),
                artifactID: "release-signoff-bundle",
                path: ".xcircuite/runs/\(runID)/release/signoff-bundle.json",
                role: .output,
                kind: .evidence,
                root: root
            )
            let plan = FlowRunPlan(
                runID: runID,
                intent: "Authorize a reviewed signoff bundle",
                stages: [
                    FlowStageDefinition(
                        stageID: stageID,
                        displayName: "Release signoff",
                        requiresApproval: true
                    ),
                ]
            )
            let planReference = try Self.write(
                try Self.encode(plan),
                artifactID: "run-plan",
                path: ".xcircuite/runs/\(runID)/plan.json",
                role: .input,
                kind: .other,
                root: root
            )
            let reviewedResult = FlowStageResult(
                stageID: stageID,
                status: .blocked,
                gates: [
                    FlowGateResult(gateID: "signoff", status: .passed),
                    FlowGateResult(gateID: "approval", status: .incomplete),
                ],
                artifacts: [bundle]
            )
            let reviewedData = try Self.encode(reviewedResult)
            let reviewedDigest = try SHA256ContentDigester().digest(data: reviewedData)
            let reviewedReference = try Self.write(
                reviewedData,
                artifactID: "approval-review-release-signoff",
                path: ".xcircuite/runs/\(runID)/review/approval-inputs/"
                    + "\(stageID)-\(reviewedDigest.hexadecimalValue).json",
                role: .output,
                kind: .report,
                root: root
            )
            let decidedAt = Date(timeIntervalSince1970: 1_900_000_000)
            approval = FlowApprovalRecord(
                runID: runID,
                stageID: stageID,
                verdict: .approved,
                reviewer: "release-reviewer",
                reviewerKind: .human,
                note: "Reviewed signoff evidence.",
                createdAt: decidedAt,
                evidence: FlowApprovalEvidenceBinding(
                    plan: planReference,
                    stageResult: reviewedReference
                )
            )
            let approvalReference = try Self.write(
                try Self.encode(approval),
                artifactID: "approval-\(stageID)",
                path: ".xcircuite/runs/\(runID)/approvals/\(stageID).json",
                role: .output,
                kind: .report,
                root: root
            )
            let action = FlowRunActionRecord(
                actionID: "approval-\(stageID)-\(approvalReference.digest.hexadecimalValue)",
                runID: runID,
                stageID: stageID,
                actor: FlowRunActor(kind: .human, identifier: approval.reviewer),
                actionKind: FlowRunReviewDecisionKind.approval.rawValue,
                status: .succeeded,
                inputs: [planReference, reviewedReference],
                outputs: [approvalReference],
                context: FlowRunActionContext(
                    reviewDecision: .init(
                        kind: .approval,
                        decision: FlowApprovalRecord.Verdict.approved.rawValue,
                        targetID: stageID,
                        targetPath: "runs/\(runID)/approvals/\(stageID).json",
                        reason: approval.note
                    )
                ),
                createdAt: decidedAt
            )
            let retentionAction = FlowRunActionRecord(
                actionID: "approval-review-\(stageID)-\(reviewedReference.digest.hexadecimalValue)",
                runID: runID,
                stageID: stageID,
                actor: FlowRunActor(
                    kind: .system,
                    identifier: "design-flow-kernel"
                ),
                actionKind: "approval.review.retain",
                status: .succeeded,
                inputs: [planReference],
                outputs: [reviewedReference],
                createdAt: Date(timeIntervalSince1970: 1_899_999_990)
            )
            let artifacts = [
                bundle,
                planReference,
            ]
            let startedAt = Date(timeIntervalSince1970: 1_899_999_900)
            let finishedAt = Date(timeIntervalSince1970: 1_899_999_990)
            let manifest = try FlowRunManifest(
                runID: runID,
                status: .blocked,
                actor: FlowRunActor(kind: .agent, identifier: "release-agent"),
                intent: plan.intent,
                createdAt: startedAt,
                updatedAt: finishedAt,
                startedAt: startedAt,
                finishedAt: finishedAt,
                artifacts: artifacts
            )
            let ledger = FlowRunLedger(
                runID: runID,
                runManifest: manifest,
                plan: plan,
                stages: [reviewedResult],
                artifacts: artifacts,
                actions: [retentionAction, action],
                approvals: [approval]
            )
            let reader = LocalReleaseArtifactReader(workspaceRoot: root)
            authenticator = AttestedReleaseApprovalAuthenticator(
                ledgerReader: StubReleaseApprovalLedgerReader(ledger: ledger),
                artifactReader: reader
            )
        }

        func remove() {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove approval authentication fixture: \(error)")
            }
        }

        private static func encode<T: Encodable>(_ value: T) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(value)
        }

        private static func write(
            _ data: Data,
            artifactID: String,
            path: String,
            role: ArtifactRole,
            kind: ArtifactKind,
            root: URL
        ) throws -> ArtifactReference {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            let referenced = try LocalArtifactReferencer().reference(
                ArtifactLocator(
                    location: try ArtifactLocation(workspaceRelativePath: path),
                    role: role,
                    kind: kind,
                    format: .json
                ),
                relativeTo: root
            )
            return ArtifactReference(
                id: try ArtifactID(rawValue: artifactID),
                locator: referenced.locator,
                digest: referenced.digest,
                byteCount: referenced.byteCount,
                producer: referenced.producer
            )
        }
    }
}

private struct StubReleaseApprovalLedgerReader: ReleaseApprovalLedgerReading {
    let ledger: FlowRunLedger

    func loadAttestedRunLedger(runID: String) async throws -> FlowRunLedger {
        guard ledger.runID == runID else {
            throw ReleaseApprovalAuthenticationError.ledgerScopeMismatch
        }
        return ledger
    }
}
