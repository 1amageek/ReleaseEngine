import Foundation
import CircuiteFoundation
import ReleaseCore
import PhysicalDesignCore
import PDKCore

public struct TapeoutRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 5

    public var schemaVersion: Int
    public var runID: String
    public var inputBindings: [ReleaseArtifactBinding]

    public var signoffBundle: SignoffBundleReference
    public var exactReleaseBundle: ReleaseExactBundle
    public var authorizationBinding: ReleaseArtifactBinding
    public var physicalDesign: PhysicalDesignReference
    public var pdk: PDKReference
    public var pdkManifestBinding: ReleaseArtifactBinding
    public var streamOut: StreamOutGenerationRequest
    public var foundryID: String
    public var projectRoot: String?
    public var handoffOutput: ReleaseArtifactDestination
    public var evidenceBindings: [ReleaseArtifactBinding]

    public var inputs: [ArtifactReference] { inputBindings.map(\.reference) }
    public var authorization: ArtifactReference { authorizationBinding.reference }
    public var evidence: [ArtifactReference] { evidenceBindings.map(\.reference) }

    public init(
        runID: String,
        inputBindings: [ReleaseArtifactBinding],
        signoffBundle: SignoffBundleReference,
        exactReleaseBundle: ReleaseExactBundle,
        authorizationBinding: ReleaseArtifactBinding,
        physicalDesign: PhysicalDesignReference,
        pdk: PDKReference,
        pdkManifestBinding: ReleaseArtifactBinding,
        streamOut: StreamOutGenerationRequest,
        foundryID: String,
        projectRoot: String? = nil,
        handoffOutput: ReleaseArtifactDestination,
        evidenceBindings: [ReleaseArtifactBinding] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputBindings = inputBindings
        self.signoffBundle = signoffBundle
        self.exactReleaseBundle = exactReleaseBundle
        self.authorizationBinding = authorizationBinding
        self.physicalDesign = physicalDesign
        self.pdk = pdk
        self.pdkManifestBinding = pdkManifestBinding
        self.streamOut = streamOut
        self.foundryID = foundryID
        self.projectRoot = projectRoot
        self.handoffOutput = handoffOutput
        self.evidenceBindings = evidenceBindings
    }
}
