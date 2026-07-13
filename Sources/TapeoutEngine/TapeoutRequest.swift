import Foundation
import CircuiteFoundation
import ReleaseCore
import PhysicalDesignCore
import PDKCore

public struct TapeoutRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]

    public var signoffBundle: SignoffBundleReference
    public var physicalDesign: PhysicalDesignReference
    public var pdk: PDKReference
    public var streamOut: StreamOutRequest?
    public var foundryID: String
    public var projectRoot: String?
    public var releaseArtifact: ArtifactReference?
    public var evidence: [ArtifactReference]

    public init(
        runID: String,
        inputs: [ArtifactReference],
        signoffBundle: SignoffBundleReference,
        physicalDesign: PhysicalDesignReference,
        pdk: PDKReference,
        streamOut: StreamOutRequest? = nil,
        foundryID: String = "",
        projectRoot: String? = nil,
        releaseArtifact: ArtifactReference? = nil,
        evidence: [ArtifactReference] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.signoffBundle = signoffBundle
        self.physicalDesign = physicalDesign
        self.pdk = pdk
        self.streamOut = streamOut
        self.foundryID = foundryID
        self.projectRoot = projectRoot
        self.releaseArtifact = releaseArtifact
        self.evidence = evidence
    }
}
