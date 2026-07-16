import Foundation
import LogicIR
import CircuiteFoundation
import ReleaseCore

public struct SignoffRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]

    public var profileID: String
    public var designKind: ReleaseDesignKind
    public var designDigest: String
    public var designProvenance: LogicDesignProvenance?
    public var pdkDigest: String
    public var evidence: [ArtifactReference]
    public var evidenceRecords: [ReleaseSignoffEvidenceReference]
    public var waivers: [SignoffWaiver]
    public var projectRoot: String?
    public var finalLayoutDigest: String?
    public var bundleArtifact: ArtifactReference?
    public var bundleIssuedAt: Date?

    public init(
        runID: String,
        inputs: [ArtifactReference],
        profileID: String,
        designDigest: String,
        designProvenance: LogicDesignProvenance? = nil,
        pdkDigest: String,
        evidence: [ArtifactReference],
        designKind: ReleaseDesignKind = .digital,
        evidenceRecords: [ReleaseSignoffEvidenceReference] = [],
        waivers: [SignoffWaiver] = [],
        projectRoot: String? = nil,
        finalLayoutDigest: String? = nil,
        bundleArtifact: ArtifactReference? = nil,
        bundleIssuedAt: Date? = nil
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
        self.bundleIssuedAt = bundleIssuedAt
    }
}
