import Foundation
import QualificationEngine
import ToolQualification
import XcircuitePackage

public struct ReleaseProfileStageEvidence: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var stageID: String
    public var runID: String
    public var status: XcircuiteEngineExecutionStatus
    public var resultArtifact: XcircuiteFileReference
    public var profileID: String?
    public var processProfileID: String?
    public var designDigest: String?
    public var pdkDigest: String?
    public var approved: Bool
    public var qualified: Bool
    public var qualificationLevel: ToolQualificationLevel?
    public var promotionStatus: ReleaseQualificationPromotionStatus?
    public var qualificationDigest: String?
    public var qualificationScope: ToolQualificationScope?

    public init(
        stageID: String,
        runID: String,
        status: XcircuiteEngineExecutionStatus,
        resultArtifact: XcircuiteFileReference,
        profileID: String? = nil,
        processProfileID: String? = nil,
        designDigest: String? = nil,
        pdkDigest: String? = nil,
        approved: Bool = false,
        qualified: Bool = false,
        qualificationLevel: ToolQualificationLevel? = nil,
        promotionStatus: ReleaseQualificationPromotionStatus? = nil,
        qualificationDigest: String? = nil,
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
        self.designDigest = designDigest
        self.pdkDigest = pdkDigest
        self.approved = approved
        self.qualified = qualified
        self.qualificationLevel = qualificationLevel
        self.promotionStatus = promotionStatus
        self.qualificationDigest = qualificationDigest
        self.qualificationScope = qualificationScope
    }
}
