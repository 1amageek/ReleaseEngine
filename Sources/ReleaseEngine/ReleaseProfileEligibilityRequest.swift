import Foundation
import ReleaseCore
import ToolQualification
import CircuiteFoundation

public struct ReleaseProfileEligibilityRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]
    public var profileID: String
    public var processProfileID: String
    public var requiredQualificationLevel: ToolQualificationLevel
    public var requiredPromotionStatus: ReleaseProfileRequiredPromotionStatus
    public var requiredQualificationScope: ToolQualificationScope?
    public var signoff: ReleaseProfileStageEvidence
    public var qualification: ReleaseProfileStageEvidence
    public var tapeout: ReleaseProfileStageEvidence
    public var decisionPacketArtifact: ArtifactReference
    public var approval: ReleaseApprovalRecord

    public init(
        runID: String,
        profileID: String,
        processProfileID: String,
        requiredQualificationLevel: ToolQualificationLevel = .productionEligible,
        requiredPromotionStatus: ReleaseProfileRequiredPromotionStatus = .productionEligible,
        requiredQualificationScope: ToolQualificationScope? = nil,
        signoff: ReleaseProfileStageEvidence,
        qualification: ReleaseProfileStageEvidence,
        tapeout: ReleaseProfileStageEvidence,
        decisionPacketArtifact: ArtifactReference,
        approval: ReleaseApprovalRecord,
        inputs: [ArtifactReference]? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.inputs = inputs ?? [
            signoff.resultArtifact,
            qualification.resultArtifact,
            tapeout.resultArtifact,
            decisionPacketArtifact,
        ]
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
    }
}
