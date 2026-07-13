import CircuiteFoundation
import Foundation
import QualificationEngine
import ToolQualification

/// Foundation-owned evidence emitted by one release stage.
public struct FoundationReleaseProfileStageEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let stageID: String
    public let runID: String
    public let status: FoundationReleaseProfileStageStatus
    public let resultArtifact: ArtifactReference
    public let profileID: String?
    public let processProfileID: String?
    public let designRevision: ContentDigest?
    public let pdkRevision: ContentDigest?
    public let approved: Bool
    public let qualified: Bool
    public let qualificationLevel: ToolQualificationLevel?
    public let promotionStatus: ReleaseQualificationPromotionStatus?
    public let qualificationDigest: ContentDigest?
    public let qualificationScope: ToolQualificationScope?

    public init(
        stageID: String,
        runID: String,
        status: FoundationReleaseProfileStageStatus,
        resultArtifact: ArtifactReference,
        profileID: String? = nil,
        processProfileID: String? = nil,
        designRevision: ContentDigest? = nil,
        pdkRevision: ContentDigest? = nil,
        approved: Bool = false,
        qualified: Bool = false,
        qualificationLevel: ToolQualificationLevel? = nil,
        promotionStatus: ReleaseQualificationPromotionStatus? = nil,
        qualificationDigest: ContentDigest? = nil,
        qualificationScope: ToolQualificationScope? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.stageID = stageID
        self.runID = runID
        self.status = status
        self.resultArtifact = resultArtifact
        self.profileID = profileID
        self.processProfileID = processProfileID
        self.designRevision = designRevision
        self.pdkRevision = pdkRevision
        self.approved = approved
        self.qualified = qualified
        self.qualificationLevel = qualificationLevel
        self.promotionStatus = promotionStatus
        self.qualificationDigest = qualificationDigest
        self.qualificationScope = qualificationScope
    }
}
