import Foundation

public enum ReleaseExactBundleBuildError: Error, Sendable, Hashable {
    case signoffBundleNotReleaseReady
    case signoffReferenceMismatch(field: String)
    case signoffArtifactIdentityMismatch
    case approvalRejected
    case approvalSignoffArtifactMismatch
    case invalidBundle(ReleaseExactBundleValidationError)
}

extension ReleaseExactBundleBuildError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .signoffBundleNotReleaseReady:
            "The signoff bundle is not release ready."
        case .signoffReferenceMismatch(let field):
            "The signoff bundle reference does not match the exact \(field)."
        case .signoffArtifactIdentityMismatch:
            "The signoff artifact identity does not match the canonical signoff bundle content."
        case .approvalRejected:
            "The release approval is rejected."
        case .approvalSignoffArtifactMismatch:
            "The release approval does not bind the exact signoff bundle artifact."
        case .invalidBundle(let error):
            "The exact release bundle is invalid: \(String(describing: error))"
        }
    }
}
