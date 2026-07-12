import Foundation
import LogicIR
import XcircuitePackage
import ReleaseCore

public struct SignoffRequest: XcircuiteEngineRequest {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [XcircuiteFileReference]

    public var profileID: String
    public var designKind: ReleaseDesignKind
    public var designDigest: String
    public var designProvenance: LogicDesignProvenance?
    public var pdkDigest: String
    public var evidence: [XcircuiteFileReference]
    public var evidenceRecords: [ReleaseSignoffEvidenceReference]
    public var waivers: [SignoffWaiver]
    public var projectRoot: String?
    public var finalLayoutDigest: String?
    public var bundleArtifact: XcircuiteFileReference?

    public init(
        runID: String,
        inputs: [XcircuiteFileReference],
        profileID: String,
        designDigest: String,
        designProvenance: LogicDesignProvenance? = nil,
        pdkDigest: String,
        evidence: [XcircuiteFileReference],
        designKind: ReleaseDesignKind = .digital,
        evidenceRecords: [ReleaseSignoffEvidenceReference] = [],
        waivers: [SignoffWaiver] = [],
        projectRoot: String? = nil,
        finalLayoutDigest: String? = nil,
        bundleArtifact: XcircuiteFileReference? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.profileID = profileID
        self.designKind = designKind
        self.designDigest = designDigest
        self.designProvenance = designProvenance
        self.pdkDigest = pdkDigest
        self.evidence = evidence
        self.evidenceRecords = evidenceRecords
        self.waivers = waivers
        self.projectRoot = projectRoot
        self.finalLayoutDigest = finalLayoutDigest
        self.bundleArtifact = bundleArtifact
    }
}
