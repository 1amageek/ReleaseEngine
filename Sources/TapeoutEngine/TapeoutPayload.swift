import Foundation
import CircuiteFoundation
import ReleaseCore
import PhysicalDesignCore
import PDKCore

public struct TapeoutPayload: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var releaseArtifact: ArtifactReference?
    public var checksum: String?
    public var approved: Bool
    public var signoffBundleDigest: String?
    public var layoutDigest: String?
    public var pdkDigest: String?
    public var streamOut: StreamOutManifest?
    public var xorResult: LayoutXORResult?
    public var handoff: FoundryHandoffManifest?

    public init(
        releaseArtifact: ArtifactReference?,
        checksum: String?,
        approved: Bool = false,
        signoffBundleDigest: String? = nil,
        layoutDigest: String? = nil,
        pdkDigest: String? = nil,
        streamOut: StreamOutManifest? = nil,
        xorResult: LayoutXORResult? = nil,
        handoff: FoundryHandoffManifest? = nil,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.releaseArtifact = releaseArtifact
        self.checksum = checksum
        self.approved = approved
        self.signoffBundleDigest = signoffBundleDigest
        self.layoutDigest = layoutDigest
        self.pdkDigest = pdkDigest
        self.streamOut = streamOut
        self.xorResult = xorResult
        self.handoff = handoff
    }
}
