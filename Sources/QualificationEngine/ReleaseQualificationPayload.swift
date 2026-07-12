import Foundation
import ReleaseCore
import ToolQualification

public struct ReleaseQualificationPayload: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var qualified: Bool
    public var processProfileID: String
    public var qualificationLevel: ToolQualificationLevel
    public var qualificationScope: ToolQualificationScope?
    public var qualificationDigest: String?
    public var promotionStatus: ReleaseQualificationPromotionStatus
    public var promotionFailureCodes: [String]
    public var laneResults: [ReleaseQualificationDomainResult]
    public var blockedLanes: [String]
    public var failedLanes: [String]

    public init(
        qualified: Bool,
        processProfileID: String,
        qualificationLevel: ToolQualificationLevel,
        qualificationScope: ToolQualificationScope?,
        qualificationDigest: String?,
        promotionStatus: ReleaseQualificationPromotionStatus = .blocked,
        promotionFailureCodes: [String] = [],
        laneResults: [ReleaseQualificationDomainResult] = [],
        blockedLanes: [String] = [],
        failedLanes: [String] = [],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.qualified = qualified
        self.processProfileID = processProfileID
        self.qualificationLevel = qualificationLevel
        self.qualificationScope = qualificationScope
        self.qualificationDigest = qualificationDigest
        self.promotionStatus = promotionStatus
        self.promotionFailureCodes = promotionFailureCodes
        self.laneResults = laneResults
        self.blockedLanes = blockedLanes
        self.failedLanes = failedLanes
    }
}
