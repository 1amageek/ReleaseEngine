import Foundation

public struct RetainedCorpusSuite: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public struct Requirements: Sendable, Hashable, Codable {
        public var domainIDs: [String]
        public var requireExternalOracles: Bool
        public var requiredArtifacts: [String]

        public init(
            domainIDs: [String],
            requireExternalOracles: Bool,
            requiredArtifacts: [String]
        ) {
            self.domainIDs = domainIDs
            self.requireExternalOracles = requireExternalOracles
            self.requiredArtifacts = requiredArtifacts
        }
    }

    public var schemaVersion: Int
    public var suiteID: String
    public var createdAt: String?
    public var sourceDashboardPath: String?
    public var lanes: [ReleaseQualificationLane]
    public var requirements: Requirements?

    public init(
        suiteID: String,
        lanes: [ReleaseQualificationLane],
        createdAt: String? = nil,
        sourceDashboardPath: String? = nil,
        requirements: Requirements? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.createdAt = createdAt
        self.sourceDashboardPath = sourceDashboardPath
        self.lanes = lanes
        self.requirements = requirements
    }

    public var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && !suiteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lanes.isEmpty
            && Set(lanes.map { $0.laneID }).count == lanes.count
            && lanes.allSatisfy { $0.isValid }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case suiteID
        case createdAt
        case sourceDashboardPath
        case lanes
        case requirements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        suiteID = try container.decode(String.self, forKey: .suiteID)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        sourceDashboardPath = try container.decodeIfPresent(String.self, forKey: .sourceDashboardPath)
        lanes = try container.decode([ReleaseQualificationLane].self, forKey: .lanes)
        requirements = try container.decodeIfPresent(Requirements.self, forKey: .requirements)
    }
}
