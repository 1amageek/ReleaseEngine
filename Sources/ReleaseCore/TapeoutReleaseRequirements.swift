import Foundation

public struct TapeoutReleaseRequirements: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var expectedTopCell: String
    public var expectedUnitsPerDatabaseUnit: Double
    public var requiredLayerIDs: [String]
    public var requiredPadCells: [String]
    public var requiredSeal: String
    public var requireExactStreamIdentity: Bool

    public init(
        expectedTopCell: String,
        expectedUnitsPerDatabaseUnit: Double,
        requiredLayerIDs: [String] = [],
        requiredPadCells: [String] = [],
        requiredSeal: String,
        requireExactStreamIdentity: Bool = true,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.expectedTopCell = expectedTopCell
        self.expectedUnitsPerDatabaseUnit = expectedUnitsPerDatabaseUnit
        self.requiredLayerIDs = requiredLayerIDs
        self.requiredPadCells = requiredPadCells
        self.requiredSeal = requiredSeal
        self.requireExactStreamIdentity = requireExactStreamIdentity
    }
}
