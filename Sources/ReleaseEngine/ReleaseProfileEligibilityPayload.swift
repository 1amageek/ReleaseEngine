import Foundation
import ToolQualification

public struct ReleaseProfileEligibilityPayload: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var eligible: Bool
    public var status: ReleaseProfileEligibilityStatus
    public var profileID: String
    public var processProfileID: String
    public var requiredQualificationLevel: ToolQualificationLevel
    public var requiredPromotionStatus: ReleaseProfileRequiredPromotionStatus
    public var qualificationDigest: String?
    public var decisionPacketDigest: String?
    public var reviewedArtifactDigests: [String]
    public var evidenceDigest: String?
    public var failureCodes: [String]

    public init(
        eligible: Bool,
        status: ReleaseProfileEligibilityStatus,
        profileID: String,
        processProfileID: String,
        requiredQualificationLevel: ToolQualificationLevel,
        requiredPromotionStatus: ReleaseProfileRequiredPromotionStatus,
        qualificationDigest: String? = nil,
        decisionPacketDigest: String? = nil,
        reviewedArtifactDigests: [String] = [],
        evidenceDigest: String? = nil,
        failureCodes: [String] = [],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.eligible = eligible
        self.status = status
        self.profileID = profileID
        self.processProfileID = processProfileID
        self.requiredQualificationLevel = requiredQualificationLevel
        self.requiredPromotionStatus = requiredPromotionStatus
        self.qualificationDigest = qualificationDigest
        self.decisionPacketDigest = decisionPacketDigest
        self.reviewedArtifactDigests = reviewedArtifactDigests
        self.evidenceDigest = evidenceDigest
        self.failureCodes = failureCodes
    }
}
