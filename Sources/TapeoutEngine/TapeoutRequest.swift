import Foundation
import CircuiteFoundation
import ReleaseCore
import PhysicalDesignCore
import PDKCore

public struct TapeoutRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]

    public var signoffBundle: SignoffBundleReference
    public var authorization: ArtifactReference
    public var physicalDesign: PhysicalDesignReference
    public var pdk: PDKReference
    public var streamOut: StreamOutGenerationRequest
    public var foundryID: String
    public var projectRoot: String?
    public var handoffOutput: ArtifactLocator
    public var evidence: [ArtifactReference]

    public init(
        runID: String,
        inputs: [ArtifactReference],
        signoffBundle: SignoffBundleReference,
        authorization: ArtifactReference,
        physicalDesign: PhysicalDesignReference,
        pdk: PDKReference,
        streamOut: StreamOutGenerationRequest,
        foundryID: String,
        projectRoot: String? = nil,
        handoffOutput: ArtifactLocator,
        evidence: [ArtifactReference] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.signoffBundle = signoffBundle
        self.authorization = authorization
        self.physicalDesign = physicalDesign
        self.pdk = pdk
        self.streamOut = streamOut
        self.foundryID = foundryID
        self.projectRoot = projectRoot
        self.handoffOutput = handoffOutput
        self.evidence = evidence
    }
}
