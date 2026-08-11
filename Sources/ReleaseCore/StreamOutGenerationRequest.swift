import Foundation
import CircuiteFoundation

public struct StreamOutGenerationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var output: ReleaseArtifactDestination
    public var topCell: String
    public var unitsPerDatabaseUnit: Double
    public var layerMap: [String: Int]
    public var hierarchyDepth: Int
    public var seal: String
    public var padCells: [String]
    public var generatorID: String
    public var generatorVersion: String
    public var requirements: TapeoutReleaseRequirements

    public init(
        output: ReleaseArtifactDestination,
        topCell: String,
        unitsPerDatabaseUnit: Double,
        layerMap: [String: Int],
        hierarchyDepth: Int,
        seal: String,
        padCells: [String],
        generatorID: String,
        generatorVersion: String,
        requirements: TapeoutReleaseRequirements,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.output = output
        self.topCell = topCell
        self.unitsPerDatabaseUnit = unitsPerDatabaseUnit
        self.layerMap = layerMap
        self.hierarchyDepth = hierarchyDepth
        self.seal = seal
        self.padCells = padCells
        self.generatorID = generatorID
        self.generatorVersion = generatorVersion
        self.requirements = requirements
    }
}
