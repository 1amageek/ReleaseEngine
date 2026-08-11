import Foundation
import CircuiteFoundation

public struct StreamOutManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var streamedArtifact: ReleaseArtifactBinding
    public var topCell: String
    public var unitsPerDatabaseUnit: Double
    public var layerMap: [String: Int]
    public var hierarchyDepth: Int
    public var seal: String
    public var padCells: [String]
    public var generatedBy: String

    public init(
        streamedArtifact: ReleaseArtifactBinding,
        topCell: String,
        unitsPerDatabaseUnit: Double,
        layerMap: [String: Int],
        hierarchyDepth: Int,
        seal: String,
        padCells: [String],
        generatedBy: String,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.streamedArtifact = streamedArtifact
        self.topCell = topCell
        self.unitsPerDatabaseUnit = unitsPerDatabaseUnit
        self.layerMap = layerMap
        self.hierarchyDepth = hierarchyDepth
        self.seal = seal
        self.padCells = padCells
        self.generatedBy = generatedBy
    }
}
