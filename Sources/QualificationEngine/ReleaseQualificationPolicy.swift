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
        requiredQualificationScope: ToolQualificationScope,
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
            && requiredLanes.allSatisfy { !$0.laneID.isEmpty && !$0.domain.isEmpty }
            && requiredEvidenceKinds.count > 0
            && requiredQualifiedEvidenceKinds.allSatisfy { requiredEvidenceKinds.contains($0) }
            && requiredQualificationScope.isComplete
            && minimumCaseCount >= 1
            && minimumCoverageTagCount >= 1
            && minimumCoveredRequiredCoverageTagCount >= 1
            && probabilities.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
            && maximumEvidenceAgeSeconds.isFinite
            && maximumEvidenceAgeSeconds > 0
    }
}
