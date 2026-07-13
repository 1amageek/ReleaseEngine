import Foundation
import ReleaseCore
import CircuiteFoundation

public struct ReleaseQualificationDomainResult: Sendable, Hashable, Codable {
    public var laneID: String
    public var domain: String
    public var kind: ReleaseQualificationLaneKind
    public var status: String
    public var qualified: Bool
    public var caseCount: Int?
    public var coverageTagCount: Int?
    public var coveredRequiredCoverageTagCount: Int?
    public var passRate: Double?
    public var oracleAgreementRate: Double?
    public var durationBudgetPassRate: Double?
    public var failureCodes: [String]
    public var corpusArtifact: ArtifactReference?
    public var reportArtifact: ArtifactReference?
    public var evidenceArtifact: ArtifactReference?

    public init(
        laneID: String,
        domain: String,
        kind: ReleaseQualificationLaneKind,
        status: String,
        qualified: Bool,
        caseCount: Int?,
        coverageTagCount: Int?,
        coveredRequiredCoverageTagCount: Int?,
        passRate: Double?,
        oracleAgreementRate: Double?,
        durationBudgetPassRate: Double?,
        failureCodes: [String] = [],
        corpusArtifact: ArtifactReference? = nil,
        reportArtifact: ArtifactReference? = nil,
        evidenceArtifact: ArtifactReference? = nil
    ) {
        self.laneID = laneID
        self.domain = domain
        self.kind = kind
        self.status = status
        self.qualified = qualified
        self.caseCount = caseCount
        self.coverageTagCount = coverageTagCount
        self.coveredRequiredCoverageTagCount = coveredRequiredCoverageTagCount
        self.passRate = passRate
        self.oracleAgreementRate = oracleAgreementRate
        self.durationBudgetPassRate = durationBudgetPassRate
        self.failureCodes = failureCodes
        self.corpusArtifact = corpusArtifact
        self.reportArtifact = reportArtifact
        self.evidenceArtifact = evidenceArtifact
    }
}
