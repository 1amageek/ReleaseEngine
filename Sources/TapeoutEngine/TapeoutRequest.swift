import Foundation
import XcircuitePackage
import ReleaseCore
import PhysicalDesignCore
import PDKCore

public struct TapeoutRequest: XcircuiteEngineRequest {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [XcircuiteFileReference]

    public var signoffBundle: SignoffBundleReference
    public var physicalDesign: PhysicalDesignReference
    public var pdk: PDKReference
    public var streamOut: StreamOutRequest?
    public var foundryID: String
    public var projectRoot: String?
    public var releaseArtifact: XcircuiteFileReference?
    public var evidence: [XcircuiteFileReference]

    public init(
        runID: String,
        inputs: [XcircuiteFileReference],
        signoffBundle: SignoffBundleReference,
        physicalDesign: PhysicalDesignReference,
        pdk: PDKReference,
        streamOut: StreamOutRequest? = nil,
        foundryID: String = "",
        projectRoot: String? = nil,
        releaseArtifact: XcircuiteFileReference? = nil,
        evidence: [XcircuiteFileReference] = []
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
