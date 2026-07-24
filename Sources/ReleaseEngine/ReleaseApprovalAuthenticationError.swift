import Foundation

public enum ReleaseApprovalAuthenticationError: Error, Sendable, Equatable {
    case ledgerUnreadable(String)
    case ledgerScopeMismatch
    case approvalNotRetained
    case approvalArtifactNotRetained
    case approvalArtifactMismatch
    case approvalActionNotRetained
    case approvalActionMismatch
    case planEvidenceMismatch
    case reviewedStageResultNotRetained
    case reviewedStageResultMismatch
    case signoffBundleNotReviewed
}

extension ReleaseApprovalAuthenticationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .ledgerUnreadable(let detail):
            "The canonical run ledger could not be read: \(detail)"
        case .ledgerScopeMismatch:
            "The canonical run ledger does not match the requested run."
        case .approvalNotRetained:
            "The approval is not uniquely retained by the canonical run ledger."
        case .approvalArtifactNotRetained:
            "The canonical approval artifact is not uniquely retained by the run ledger."
        case .approvalArtifactMismatch:
            "The retained approval artifact does not match the supplied approval."
        case .approvalActionNotRetained:
            "A unique successful human approval action is not retained by the run ledger."
        case .approvalActionMismatch:
            "The retained approval action is not bound to the exact reviewer, evidence, and approval artifact."
        case .planEvidenceMismatch:
            "The approval plan evidence does not match the canonical run plan."
        case .reviewedStageResultNotRetained:
            "The immutable reviewed stage-result snapshot is not retained by the canonical review action."
        case .reviewedStageResultMismatch:
            "The retained reviewed stage result is not the blocked result inspected by the human reviewer."
        case .signoffBundleNotReviewed:
            "The reviewed stage result does not retain the exact signoff bundle being authorized."
        }
    }
}
