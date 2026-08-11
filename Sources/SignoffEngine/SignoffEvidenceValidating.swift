import Foundation
import CircuiteFoundation
import ReleaseCore

public protocol SignoffEvidenceValidating: Sendable {
    func validate(
        evidence: [ReleaseSignoffEvidenceReference],
        bindings: [ReleaseArtifactBinding],
        projectRoot: URL?,
        rootID: ArtifactRootID,
        designDigest: String,
        pdkDigest: String,
        profile: ReleaseSignoffProfile,
        evaluatedAt: Date
    ) async -> SignoffEvidenceValidationResult
}
