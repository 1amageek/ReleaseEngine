import Foundation
import PhysicalDesignCore
import XcircuitePackage

public struct StreamOutRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var sourceLayout: PhysicalDesignReference
    public var manifest: StreamOutManifest
    public var projectRoot: String?
    public var requirements: TapeoutReleaseRequirements

    public init(
        sourceLayout: PhysicalDesignReference,
        manifest: StreamOutManifest,
        projectRoot: String? = nil,
        requirements: TapeoutReleaseRequirements,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.sourceLayout = sourceLayout
        self.manifest = manifest
        self.projectRoot = projectRoot
        self.requirements = requirements
    }
}
