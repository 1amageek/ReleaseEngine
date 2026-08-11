import Foundation
import LogicIR
import CircuiteFoundation
import ReleaseCore

public struct SignoffRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var runID: String
    public var inputBindings: [ReleaseArtifactBinding]

    public var profileID: String
    public var designKind: ReleaseDesignKind
    public var designDigest: String
    public var designProvenance: LogicDesignProvenance?
    public var pdkDigest: String
    public var evidenceBindings: [ReleaseArtifactBinding]
    public var evidenceRecords: [ReleaseSignoffEvidenceReference]
    public var waivers: [SignoffWaiver]
    public var projectRoot: String?
    public var finalLayoutDigest: String?
    public var bundleOutput: ReleaseArtifactDestination

    public var inputs: [ArtifactReference] { inputBindings.map(\.reference) }
    public var evidence: [ArtifactReference] { evidenceBindings.map(\.reference) }

    public init(
        runID: String,
        inputBindings: [ReleaseArtifactBinding],
        profileID: String,
        designDigest: String,
        designProvenance: LogicDesignProvenance? = nil,
        pdkDigest: String,
        evidenceBindings: [ReleaseArtifactBinding],
        designKind: ReleaseDesignKind = .digital,
        evidenceRecords: [ReleaseSignoffEvidenceReference] = [],
        waivers: [SignoffWaiver] = [],
        projectRoot: String? = nil,
        finalLayoutDigest: String? = nil,
        bundleOutput: ReleaseArtifactDestination
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputBindings = inputBindings
        self.profileID = profileID
        self.designKind = designKind
        self.designDigest = designDigest
        self.designProvenance = designProvenance
        self.pdkDigest = pdkDigest
        self.evidenceBindings = evidenceBindings
        self.evidenceRecords = evidenceRecords
        self.waivers = waivers
        self.projectRoot = projectRoot
        self.finalLayoutDigest = finalLayoutDigest
        self.bundleOutput = bundleOutput
    }
}
