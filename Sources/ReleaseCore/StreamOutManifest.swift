import Foundation
import XcircuitePackage

public struct StreamOutManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var streamedArtifact: XcircuiteFileReference
    public var topCell: String
    public var unitsPerDatabaseUnit: Double
    public var layerMap: [String: Int]
    public var hierarchyDepth: Int
    public var seal: String
    public var padCells: [String]
    public var generatedBy: String

    public init(
        streamedArtifact: XcircuiteFileReference,
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
