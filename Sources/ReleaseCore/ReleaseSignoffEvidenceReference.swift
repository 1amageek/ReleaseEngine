import Foundation
import ToolQualification
import CircuiteFoundation

public struct ReleaseSignoffEvidenceReference: Sendable, Hashable, Codable {
    public var evidenceID: String
    public var axis: ReleaseSignoffAxis
    public var artifact: ArtifactReference
    public var designDigest: String
    public var pdkDigest: String
    public var toolID: String
    public var toolVersion: String
    public var toolBinaryDigest: String
    public var inputArtifacts: [ArtifactReference]
    public var processQualification: ToolProcessQualificationEvidence
    public var disposition: SignoffEvidenceDisposition
    public var reason: String?

    public init(
        evidenceID: String,
        axis: ReleaseSignoffAxis,
        artifact: ArtifactReference,
        designDigest: String,
        pdkDigest: String,
        toolID: String,
        toolVersion: String,
        toolBinaryDigest: String,
        inputArtifacts: [ArtifactReference],
        processQualification: ToolProcessQualificationEvidence,
        disposition: SignoffEvidenceDisposition,
        reason: String? = nil
    ) {
        self.evidenceID = evidenceID
        self.axis = axis
        self.artifact = artifact
        self.designDigest = designDigest
        self.pdkDigest = pdkDigest
        self.toolID = toolID
        self.toolVersion = toolVersion
        self.toolBinaryDigest = toolBinaryDigest.lowercased()
        self.inputArtifacts = inputArtifacts
        self.processQualification = processQualification
        self.disposition = disposition
        self.reason = reason
    }
}
