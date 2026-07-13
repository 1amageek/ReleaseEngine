import CircuiteFoundation
import Foundation
import ToolQualification

/// Foundation result for release-profile eligibility evaluation.
public struct FoundationReleaseProfileEligibilityResult: Sendable, Hashable, Codable,
    ArtifactProducing, DiagnosticReporting, EvidenceProviding
{
    public let eligible: Bool
    public let status: ReleaseProfileEligibilityStatus
    public let profileID: String
    public let processProfileID: String
    public let requiredQualificationLevel: ToolQualificationLevel
    public let requiredPromotionStatus: ReleaseProfileRequiredPromotionStatus
    public let qualificationDigest: ContentDigest?
    public let decisionPacketArtifact: ArtifactReference
    public let reviewedArtifacts: [ArtifactReference]
    public let evidenceDigest: ContentDigest?
    public let failureCodes: [String]
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest

    public init(
        eligible: Bool,
        status: ReleaseProfileEligibilityStatus,
        profileID: String,
        processProfileID: String,
        requiredQualificationLevel: ToolQualificationLevel,
        requiredPromotionStatus: ReleaseProfileRequiredPromotionStatus,
        qualificationDigest: ContentDigest?,
        decisionPacketArtifact: ArtifactReference,
        reviewedArtifacts: [ArtifactReference],
        evidenceDigest: ContentDigest?,
        failureCodes: [String],
        diagnostics: [DesignDiagnostic],
        provenance: ExecutionProvenance
    ) {
        self.eligible = eligible
        self.status = status
        self.profileID = profileID
        self.processProfileID = processProfileID
        self.requiredQualificationLevel = requiredQualificationLevel
        self.requiredPromotionStatus = requiredPromotionStatus
        self.qualificationDigest = qualificationDigest
        self.decisionPacketArtifact = decisionPacketArtifact
        self.reviewedArtifacts = reviewedArtifacts
        self.evidenceDigest = evidenceDigest
        self.failureCodes = failureCodes
        self.artifacts = [decisionPacketArtifact] + reviewedArtifacts
        self.diagnostics = diagnostics
        self.evidence = EvidenceManifest(
            provenance: provenance,
            artifacts: self.artifacts
        )
    }
}
