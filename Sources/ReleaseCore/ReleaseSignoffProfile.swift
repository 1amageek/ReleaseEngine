import Foundation

public struct ReleaseSignoffProfile: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var profileID: String
    public var designKind: ReleaseDesignKind
    public var requirements: [ReleaseSignoffAxisRequirement]

    public init(
        profileID: String,
        designKind: ReleaseDesignKind,
        requirements: [ReleaseSignoffAxisRequirement],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.designKind = designKind
        self.requirements = requirements
    }

    public func requirement(for axis: ReleaseSignoffAxis) -> ReleaseSignoffAxisRequirement? {
        requirements.first { $0.axis == axis }
    }

    public var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !requirements.isEmpty
            && Set(requirements.map { $0.axis }).count == requirements.count
            && Set(requirements.map { $0.axis }) == Set(ReleaseSignoffAxis.allCases)
            && requirements.allSatisfy {
                $0.minimumEvidenceCount >= 0
                    && (!$0.required || $0.minimumEvidenceCount > 0)
            }
    }
}
