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
        public var caseResults: [RetainedCorpusCaseResult]

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
            toolEvidenceExport: ArtifactIdentity?,
            caseResults: [RetainedCorpusCaseResult] = []
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
            self.caseResults = caseResults
        }

        private enum CodingKeys: String, CodingKey {
            case domain
            case status
            case qualified
            case caseCount
            case coverageTagCount
            case coveredRequiredCoverageTagCount
            case passRate
            case oracleAgreementRate
            case durationBudgetPassRate
            case report
            case toolEvidence
            case toolEvidenceExport
            case caseResults
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.domain = try container.decode(String.self, forKey: .domain)
            self.status = try container.decodeIfPresent(String.self, forKey: .status)
            self.qualified = try container.decode(Bool.self, forKey: .qualified)
            self.caseCount = try container.decodeIfPresent(Int.self, forKey: .caseCount)
            self.coverageTagCount = try container.decodeIfPresent(Int.self, forKey: .coverageTagCount)
            self.coveredRequiredCoverageTagCount = try container.decodeIfPresent(Int.self, forKey: .coveredRequiredCoverageTagCount)
            self.passRate = try container.decodeIfPresent(Double.self, forKey: .passRate)
            self.oracleAgreementRate = try container.decodeIfPresent(Double.self, forKey: .oracleAgreementRate)
            self.durationBudgetPassRate = try container.decodeIfPresent(Double.self, forKey: .durationBudgetPassRate)
            self.report = try container.decodeIfPresent(ArtifactIdentity.self, forKey: .report)
            self.toolEvidence = try container.decodeIfPresent(ToolEvidenceObservation.self, forKey: .toolEvidence)
            self.toolEvidenceExport = try container.decodeIfPresent(ArtifactIdentity.self, forKey: .toolEvidenceExport)
            self.caseResults = try container.decodeIfPresent([RetainedCorpusCaseResult].self, forKey: .caseResults) ?? []
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
        public var caseResults: [RetainedOracleCaseResult]

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
            toolEvidenceExport: ArtifactIdentity?,
            caseResults: [RetainedOracleCaseResult] = []
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
            self.caseResults = caseResults
        }

        private enum CodingKeys: String, CodingKey {
            case domain
            case oracleBackendID
            case status
            case qualified
            case caseCount
            case coverageTagCount
            case coveredRequiredCoverageTagCount
            case passRate
            case oracleAgreementRate
            case durationBudgetPassRate
            case report
            case toolEvidence
            case toolEvidenceExport
            case caseResults
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.domain = try container.decode(String.self, forKey: .domain)
            self.oracleBackendID = try container.decodeIfPresent(String.self, forKey: .oracleBackendID)
            self.status = try container.decodeIfPresent(String.self, forKey: .status)
            self.qualified = try container.decode(Bool.self, forKey: .qualified)
            self.caseCount = try container.decodeIfPresent(Int.self, forKey: .caseCount)
            self.coverageTagCount = try container.decodeIfPresent(Int.self, forKey: .coverageTagCount)
            self.coveredRequiredCoverageTagCount = try container.decodeIfPresent(Int.self, forKey: .coveredRequiredCoverageTagCount)
            self.passRate = try container.decodeIfPresent(Double.self, forKey: .passRate)
            self.oracleAgreementRate = try container.decodeIfPresent(Double.self, forKey: .oracleAgreementRate)
            self.durationBudgetPassRate = try container.decodeIfPresent(Double.self, forKey: .durationBudgetPassRate)
            self.report = try container.decodeIfPresent(ArtifactIdentity.self, forKey: .report)
            self.toolEvidence = try container.decodeIfPresent(ToolEvidenceObservation.self, forKey: .toolEvidence)
            self.toolEvidenceExport = try container.decodeIfPresent(ArtifactIdentity.self, forKey: .toolEvidenceExport)
            self.caseResults = try container.decodeIfPresent([RetainedOracleCaseResult].self, forKey: .caseResults) ?? []
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
            && domainResults.allSatisfy { result in
                result.caseResults.allSatisfy { $0.isValid }
                    && Set(result.caseResults.map { $0.domain + "\u{1F}" + $0.caseID }).count == result.caseResults.count
            }
            && externalOracleResults.allSatisfy { result in
                result.caseResults.allSatisfy { $0.isValid }
                    && Set(result.caseResults.map { $0.domain + "\u{1F}" + $0.caseID }).count == result.caseResults.count
            }
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
