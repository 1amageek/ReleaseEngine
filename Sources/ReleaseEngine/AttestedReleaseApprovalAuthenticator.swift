import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct AttestedReleaseApprovalAuthenticator: ReleaseApprovalAuthenticating {
    private let ledgerReader: any ReleaseApprovalLedgerReading
    private let artifactReader: any ReleaseArtifactReading

    public init(
        ledgerReader: any ReleaseApprovalLedgerReading,
        artifactReader: any ReleaseArtifactReading
    ) {
        self.ledgerReader = ledgerReader
        self.artifactReader = artifactReader
    }

    public func authenticate(
        approval: FlowApprovalRecord,
        runID: String,
        signoffBundle: ArtifactReference,
        evaluatedAt: Date
    ) async throws {
        let ledger: FlowRunLedger
        do {
            ledger = try await ledgerReader.loadAttestedRunLedger(runID: runID)
        } catch {
            throw ReleaseApprovalAuthenticationError.ledgerUnreadable(
                error.localizedDescription
            )
        }
        guard ledger.runID == runID,
              ledger.runManifest.runID == runID else {
            throw ReleaseApprovalAuthenticationError.ledgerScopeMismatch
        }
        guard ledger.approvals.filter({ $0.stageID == approval.stageID }).count == 1,
              ledger.approvals.contains(approval) else {
            throw ReleaseApprovalAuthenticationError.approvalNotRetained
        }

        let actions = ledger.actions.filter {
            $0.runID == runID
                && $0.stageID == approval.stageID
                && $0.actionKind == FlowRunReviewDecisionKind.approval.rawValue
                && $0.status == .succeeded
        }
        guard actions.count == 1,
              let action = actions.first else {
            throw ReleaseApprovalAuthenticationError.approvalActionNotRetained
        }
        guard action.outputs.count == 1,
              let approvalReference = action.outputs.first,
              approvalReference.locator.role == .output,
              approvalReference.locator.kind == .report,
              approvalReference.locator.format == .json else {
            throw ReleaseApprovalAuthenticationError.approvalArtifactNotRetained
        }
        let approvalData = try await artifactReader.verifiedData(for: approvalReference)
        let retainedApproval: FlowApprovalRecord
        do {
            retainedApproval = try JSONDecoder().decode(FlowApprovalRecord.self, from: approvalData)
        } catch {
            throw ReleaseApprovalAuthenticationError.approvalArtifactMismatch
        }
        guard retainedApproval == approval else {
            throw ReleaseApprovalAuthenticationError.approvalArtifactMismatch
        }
        guard action.actor.kind == .human,
              action.actor.identifier == approval.reviewer,
              action.createdAt == approval.createdAt,
              Set(action.inputs) == Set([approval.evidence.plan, approval.evidence.stageResult]),
              action.inputs.count == 2,
              action.context.reviewDecision?.kind == .approval,
              action.context.reviewDecision?.decision == FlowApprovalRecord.Verdict.approved.rawValue,
              action.context.reviewDecision?.targetID == approval.stageID else {
            throw ReleaseApprovalAuthenticationError.approvalActionMismatch
        }

        let planData = try await artifactReader.verifiedData(for: approval.evidence.plan)
        let plan: FlowRunPlan
        do {
            plan = try JSONDecoder().decode(FlowRunPlan.self, from: planData)
        } catch {
            throw ReleaseApprovalAuthenticationError.planEvidenceMismatch
        }
        let canonicalPlans = ledger.artifacts.filter {
            $0.id.rawValue == "run-plan" && $0 == approval.evidence.plan
        }
        guard canonicalPlans.count == 1,
              plan.runID == runID,
              plan.stages.contains(where: { $0.stageID == approval.stageID }) else {
            throw ReleaseApprovalAuthenticationError.planEvidenceMismatch
        }

        let retentionActions = ledger.actions.filter {
            $0.runID == runID
                && $0.stageID == approval.stageID
                && $0.actionKind == "approval.review.retain"
                && $0.status == .succeeded
                && $0.outputs == [approval.evidence.stageResult]
        }
        guard retentionActions.count == 1,
              let retentionAction = retentionActions.first,
              retentionAction.actor.kind == .system,
              retentionAction.actor.identifier == "design-flow-kernel",
              retentionAction.inputs == [approval.evidence.plan] else {
            throw ReleaseApprovalAuthenticationError.reviewedStageResultNotRetained
        }

        let reviewedData = try await artifactReader.verifiedData(for: approval.evidence.stageResult)
        let reviewedResult: FlowStageResult
        do {
            reviewedResult = try JSONDecoder().decode(FlowStageResult.self, from: reviewedData)
        } catch {
            throw ReleaseApprovalAuthenticationError.reviewedStageResultMismatch
        }
        let approvalGates = reviewedResult.gates.filter { $0.gateID == "approval" }
        guard approval.createdAt <= evaluatedAt,
              reviewedResult.stageID == approval.stageID,
              reviewedResult.status == .blocked,
              approvalGates.count == 1,
              approvalGates.first?.status == .incomplete,
              reviewedResult.gates
                .filter({ $0.gateID != "approval" })
                .allSatisfy({ $0.status == .passed || $0.status == .waived }) else {
            throw ReleaseApprovalAuthenticationError.reviewedStageResultMismatch
        }
        guard reviewedResult.artifacts.contains(signoffBundle) else {
            throw ReleaseApprovalAuthenticationError.signoffBundleNotReviewed
        }
    }
}
