import DesignFlowKernel

/// Supplies a run ledger only after the owning persistence system has completed
/// its canonical projection, transaction-recovery, and artifact attestation.
public protocol ReleaseApprovalLedgerReading: Sendable {
    func loadAttestedRunLedger(runID: String) async throws -> FlowRunLedger
}
