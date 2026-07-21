import Foundation
import CircuiteFoundation
import ReleaseCore
import PhysicalDesignCore
import PDKCore

public struct TapeoutPayload: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var handoffArtifact: ArtifactReference?
    public var checksum: String?
    public var completed: Bool
    public var layoutDigest: String?
    public var pdkDigest: String?
    public var streamOut: StreamOutManifest?
    public var xorResult: LayoutXORResult?
    public var handoff: FoundryHandoffManifest?

    public init(
        handoffArtifact: ArtifactReference?,
        checksum: String?,
        completed: Bool = false,
        layoutDigest: String? = nil,
        pdkDigest: String? = nil,
        streamOut: StreamOutManifest? = nil,
        xorResult: LayoutXORResult? = nil,
        handoff: FoundryHandoffManifest? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.handoffArtifact = handoffArtifact
        self.checksum = checksum
        self.completed = completed
        self.layoutDigest = layoutDigest
        self.pdkDigest = pdkDigest
        self.streamOut = streamOut
        self.xorResult = xorResult
        self.handoff = handoff
    }
}
