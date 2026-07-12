import Foundation
import ToolQualification

public struct ReleaseQualificationPolicy: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var policyID: String
    public var processProfileID: String
    public var requiredLanes: [ReleaseQualificationLane]
    public var requiredEvidenceKinds: [ToolEvidenceKind]
    public var requiredQualifiedEvidenceKinds: [ToolEvidenceKind]
    public var requiredQualificationLevel: ToolQualificationLevel
    public var requiredQualificationScope: ToolQualificationScope
    public var requireIndependentProcessQualification: Bool
    public var minimumCaseCount: Int
    public var minimumCoverageTagCount: Int
    public var minimumCoveredRequiredCoverageTagCount: Int
    public var minimumPassRate: Double
    public var minimumOracleAgreementRate: Double
    public var minimumDurationBudgetPassRate: Double
    public var maximumEvidenceAgeSeconds: TimeInterval

    public init(
        policyID: String,
        processProfileID: String,
        requiredLanes: [ReleaseQualificationLane],
        requiredEvidenceKinds: [ToolEvidenceKind] = [.corpus],
        requiredQualifiedEvidenceKinds: [ToolEvidenceKind] = [.corpus],
        requiredQualificationLevel: ToolQualificationLevel = .corpusChecked,
        requiredQualificationScope: ToolQualificationScope = ToolQualificationScope(
            implementationID: "",
            binaryDigest: "",
            algorithmVersion: "",
            processProfileID: "",
            deckDigest: ""
        ),
        requireIndependentProcessQualification: Bool = false,
        minimumCaseCount: Int = 1,
        minimumCoverageTagCount: Int = 1,
        minimumCoveredRequiredCoverageTagCount: Int = 1,
        minimumPassRate: Double = 1,
        minimumOracleAgreementRate: Double = 1,
        minimumDurationBudgetPassRate: Double = 1,
        maximumEvidenceAgeSeconds: TimeInterval = 30 * 24 * 60 * 60,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.policyID = policyID
        self.processProfileID = processProfileID
        self.requiredLanes = requiredLanes
        self.requiredEvidenceKinds = requiredEvidenceKinds
        self.requiredQualifiedEvidenceKinds = requiredQualifiedEvidenceKinds
        self.requiredQualificationLevel = requiredQualificationLevel
        self.requiredQualificationScope = requiredQualificationScope
        self.requireIndependentProcessQualification = requireIndependentProcessQualification
        self.minimumCaseCount = minimumCaseCount
        self.minimumCoverageTagCount = minimumCoverageTagCount
        self.minimumCoveredRequiredCoverageTagCount = minimumCoveredRequiredCoverageTagCount
        self.minimumPassRate = minimumPassRate
        self.minimumOracleAgreementRate = minimumOracleAgreementRate
        self.minimumDurationBudgetPassRate = minimumDurationBudgetPassRate
        self.maximumEvidenceAgeSeconds = maximumEvidenceAgeSeconds
    }

    public var isValid: Bool {
        let probabilities = [minimumPassRate, minimumOracleAgreementRate, minimumDurationBudgetPassRate]
        return schemaVersion == Self.currentSchemaVersion
            && !policyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !processProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !requiredLanes.isEmpty
            && Set(requiredLanes.map { $0.laneID }).count == requiredLanes.count
            && requiredLanes.allSatisfy { lane in
                guard lane.isValid else { return false }
                guard lane.kind == .externalOracle else { return true }
                return !(lane.corpusSpecPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !(lane.reportPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !lane.requiredProbeIDs.isEmpty
            }
            && requiredEvidenceKinds.count > 0
            && Set(requiredEvidenceKinds).count == requiredEvidenceKinds.count
            && Set(requiredQualifiedEvidenceKinds).count == requiredQualifiedEvidenceKinds.count
            && requiredQualifiedEvidenceKinds.allSatisfy { requiredEvidenceKinds.contains($0) }
            && requiredQualificationScope.isComplete
            && (!requireIndependentProcessQualification || (
                requiredQualificationScope.isCompleteForPDK
                    && requiredEvidenceKinds.contains(.productionApproval)
                    && requiredQualifiedEvidenceKinds.contains(.productionApproval)
            ))
            && minimumCaseCount >= 1
            && minimumCoverageTagCount >= 1
            && minimumCoveredRequiredCoverageTagCount >= 1
            && probabilities.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
            && maximumEvidenceAgeSeconds.isFinite
            && maximumEvidenceAgeSeconds > 0
            && (requiredQualificationLevel < .oracleChecked || requiredLanes.contains { $0.kind == .externalOracle })
            && (requiredQualificationLevel < .productionEligible || requiredQualifiedEvidenceKinds.contains(.productionApproval))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case policyID
        case processProfileID
        case requiredLanes
        case requiredEvidenceKinds
        case requiredQualifiedEvidenceKinds
        case requiredQualificationLevel
        case requiredQualificationScope
        case requireIndependentProcessQualification
        case minimumCaseCount
        case minimumCoverageTagCount
        case minimumCoveredRequiredCoverageTagCount
        case minimumPassRate
        case minimumOracleAgreementRate
        case minimumDurationBudgetPassRate
        case maximumEvidenceAgeSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            policyID: try container.decode(String.self, forKey: .policyID),
            processProfileID: try container.decode(String.self, forKey: .processProfileID),
            requiredLanes: try container.decode([ReleaseQualificationLane].self, forKey: .requiredLanes),
            requiredEvidenceKinds: try container.decode([ToolEvidenceKind].self, forKey: .requiredEvidenceKinds),
            requiredQualifiedEvidenceKinds: try container.decode([ToolEvidenceKind].self, forKey: .requiredQualifiedEvidenceKinds),
            requiredQualificationLevel: try container.decode(ToolQualificationLevel.self, forKey: .requiredQualificationLevel),
            requiredQualificationScope: try container.decode(ToolQualificationScope.self, forKey: .requiredQualificationScope),
            requireIndependentProcessQualification: try container.decodeIfPresent(Bool.self, forKey: .requireIndependentProcessQualification) ?? false,
            minimumCaseCount: try container.decode(Int.self, forKey: .minimumCaseCount),
            minimumCoverageTagCount: try container.decode(Int.self, forKey: .minimumCoverageTagCount),
            minimumCoveredRequiredCoverageTagCount: try container.decode(Int.self, forKey: .minimumCoveredRequiredCoverageTagCount),
            minimumPassRate: try container.decode(Double.self, forKey: .minimumPassRate),
            minimumOracleAgreementRate: try container.decode(Double.self, forKey: .minimumOracleAgreementRate),
            minimumDurationBudgetPassRate: try container.decode(Double.self, forKey: .minimumDurationBudgetPassRate),
            maximumEvidenceAgeSeconds: try container.decode(TimeInterval.self, forKey: .maximumEvidenceAgeSeconds),
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(policyID, forKey: .policyID)
        try container.encode(processProfileID, forKey: .processProfileID)
        try container.encode(requiredLanes, forKey: .requiredLanes)
        try container.encode(requiredEvidenceKinds, forKey: .requiredEvidenceKinds)
        try container.encode(requiredQualifiedEvidenceKinds, forKey: .requiredQualifiedEvidenceKinds)
        try container.encode(requiredQualificationLevel, forKey: .requiredQualificationLevel)
        try container.encode(requiredQualificationScope, forKey: .requiredQualificationScope)
        try container.encode(requireIndependentProcessQualification, forKey: .requireIndependentProcessQualification)
        try container.encode(minimumCaseCount, forKey: .minimumCaseCount)
        try container.encode(minimumCoverageTagCount, forKey: .minimumCoverageTagCount)
        try container.encode(minimumCoveredRequiredCoverageTagCount, forKey: .minimumCoveredRequiredCoverageTagCount)
        try container.encode(minimumPassRate, forKey: .minimumPassRate)
        try container.encode(minimumOracleAgreementRate, forKey: .minimumOracleAgreementRate)
        try container.encode(minimumDurationBudgetPassRate, forKey: .minimumDurationBudgetPassRate)
        try container.encode(maximumEvidenceAgeSeconds, forKey: .maximumEvidenceAgeSeconds)
    }
}
