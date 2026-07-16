import Foundation
import ReleaseCore

public protocol SignoffEvidenceValidating: Sendable {
    func validate(
        evidence: [ReleaseSignoffEvidenceReference],
        projectRoot: URL?,
        designDigest: String,
        pdkDigest: String,
        profile: ReleaseSignoffProfile,
        evaluatedAt: Date
    ) -> SignoffEvidenceValidationResult
}
