import Foundation

public struct RetainedCorpusReport: Sendable, Hashable, Codable {
    public struct ArtifactIdentity: Sendable, Hashable, Codable {
        public var path: String
        public var sha256: String?
        public var byteCount: Int64?
        public var status: String?

        public init(path: String, sha256: String? = nil, byteCount: Int64? = nil, status: String? = nil) {
            self.path = path
            self.sha256 = sha256
            self.byteCount = byteCount
            self.status = status
        }
    }

    public struct ToolEvidenceObservation: Sendable, Hashable, Codable {
        public var evidenceID: String?
        public var checkedAt: String?
        public var failureCodes: [String]

        public init(evidenceID: String? = nil, checkedAt: String? = nil, failureCodes: [String] = []) {
            self.evidenceID = evidenceID
            self.checkedAt = checkedAt
            self.failureCodes = failureCodes
        }
    }

    public struct DomainResult: Sendable, Hashable, Codable {
        public var domain: String
        public var status: String?
        public var qualified: Bool
        public var caseCount: Int?
        public var coverageTagCount: Int?
        public var coveredRequiredCoverageTagCount: Int?
        public var passRate: Double?
        public var oracleAgreementRate: Double?
        public var durationBudgetPassRate: Double?
        public var report: ArtifactIdentity?
        public var toolEvidence: ToolEvidenceObservation?
        public var toolEvidenceExport: ArtifactIdentity?

        public init(
            domain: String,
            status: String?,
            qualified: Bool,
            caseCount: Int?,
            coverageTagCount: Int?,
            coveredRequiredCoverageTagCount: Int?,
            passRate: Double?,
            oracleAgreementRate: Double?,
            durationBudgetPassRate: Double?,
            report: ArtifactIdentity?,
            toolEvidence: ToolEvidenceObservation?,
            toolEvidenceExport: ArtifactIdentity?
        ) {
            self.domain = domain
            self.status = status
            self.qualified = qualified
            self.caseCount = caseCount
            self.coverageTagCount = coverageTagCount
            self.coveredRequiredCoverageTagCount = coveredRequiredCoverageTagCount
            self.passRate = passRate
            self.oracleAgreementRate = oracleAgreementRate
            self.durationBudgetPassRate = durationBudgetPassRate
            self.report = report
            self.toolEvidence = toolEvidence
            self.toolEvidenceExport = toolEvidenceExport
        }
    }

    public struct ExternalOracleResult: Sendable, Hashable, Codable {
        public var domain: String
        public var oracleBackendID: String?
        public var status: String?
        public var qualified: Bool
        public var caseCount: Int?
        public var coverageTagCount: Int?
        public var coveredRequiredCoverageTagCount: Int?
        public var passRate: Double?
        public var oracleAgreementRate: Double?
        public var durationBudgetPassRate: Double?
        public var report: ArtifactIdentity?
        public var toolEvidence: ToolEvidenceObservation?
        public var toolEvidenceExport: ArtifactIdentity?

        public init(
            domain: String,
            oracleBackendID: String?,
            status: String?,
            qualified: Bool,
            caseCount: Int?,
            coverageTagCount: Int?,
            coveredRequiredCoverageTagCount: Int?,
            passRate: Double?,
            oracleAgreementRate: Double?,
            durationBudgetPassRate: Double?,
            report: ArtifactIdentity?,
            toolEvidence: ToolEvidenceObservation?,
            toolEvidenceExport: ArtifactIdentity?
        ) {
            self.domain = domain
            self.oracleBackendID = oracleBackendID
            self.status = status
            self.qualified = qualified
            self.caseCount = caseCount
            self.coverageTagCount = coverageTagCount
            self.coveredRequiredCoverageTagCount = coveredRequiredCoverageTagCount
            self.passRate = passRate
            self.oracleAgreementRate = oracleAgreementRate
            self.durationBudgetPassRate = durationBudgetPassRate
            self.report = report
            self.toolEvidence = toolEvidence
            self.toolEvidenceExport = toolEvidenceExport
        }
    }

    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var status: String?
    public var createdAt: String?
    public var domainResults: [DomainResult]
    public var externalOracleResults: [ExternalOracleResult]

    public init(
        status: String?,
        createdAt: String?,
        domainResults: [DomainResult],
        externalOracleResults: [ExternalOracleResult] = [],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.createdAt = createdAt
        self.domainResults = domainResults
        self.externalOracleResults = externalOracleResults
    }

    public var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && Set(domainResults.map { $0.domain }).count == domainResults.count
            && Set(externalOracleResults.map { $0.domain + "\u{1F}" + ($0.oracleBackendID ?? "") }).count == externalOracleResults.count
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case status
        case createdAt
        case domainResults
        case externalOracleResults
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        domainResults = try container.decodeIfPresent([DomainResult].self, forKey: .domainResults) ?? []
        externalOracleResults = try container.decodeIfPresent([ExternalOracleResult].self, forKey: .externalOracleResults) ?? []
    }
}
