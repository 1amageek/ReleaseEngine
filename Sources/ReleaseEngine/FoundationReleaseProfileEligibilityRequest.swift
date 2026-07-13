import CircuiteFoundation
import Foundation
import ToolQualification

/// Canonical, artifact-oriented input for release-profile eligibility.
public struct FoundationReleaseProfileEligibilityRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: String
    public let inputs: [ArtifactReference]
    public let profileID: String
    public let processProfileID: String
    public let requiredQualificationLevel: ToolQualificationLevel
    public let requiredPromotionStatus: ReleaseProfileRequiredPromotionStatus
    public let requiredQualificationScope: ToolQualificationScope?
    public let signoff: FoundationReleaseProfileStageEvidence
    public let qualification: FoundationReleaseProfileStageEvidence
    public let tapeout: FoundationReleaseProfileStageEvidence
    public let decisionPacketArtifact: ArtifactReference
    public let approval: FoundationReleaseProfileApproval

    public init(
        runID: String,
        profileID: String,
        processProfileID: String,
        requiredQualificationLevel: ToolQualificationLevel = .productionEligible,
        requiredPromotionStatus: ReleaseProfileRequiredPromotionStatus = .productionEligible,
        requiredQualificationScope: ToolQualificationScope? = nil,
        signoff: FoundationReleaseProfileStageEvidence,
        qualification: FoundationReleaseProfileStageEvidence,
        tapeout: FoundationReleaseProfileStageEvidence,
        decisionPacketArtifact: ArtifactReference,
        approval: FoundationReleaseProfileApproval,
        inputs: [ArtifactReference]? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.profileID = profileID
        self.processProfileID = processProfileID
        self.requiredQualificationLevel = requiredQualificationLevel
        self.requiredPromotionStatus = requiredPromotionStatus
        self.requiredQualificationScope = requiredQualificationScope
        self.signoff = signoff
        self.qualification = qualification
        self.tapeout = tapeout
        self.decisionPacketArtifact = decisionPacketArtifact
        self.approval = approval
        self.inputs = inputs ?? [
            signoff.resultArtifact,
            qualification.resultArtifact,
            tapeout.resultArtifact,
            decisionPacketArtifact,
        ]
    }
}
