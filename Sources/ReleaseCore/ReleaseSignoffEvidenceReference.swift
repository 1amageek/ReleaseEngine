import Foundation
import ToolQualification
import XcircuitePackage

public struct ReleaseSignoffEvidenceReference: Sendable, Hashable, Codable {
    public var evidenceID: String
    public var axis: ReleaseSignoffAxis
    public var artifact: XcircuiteFileReference
    public var designDigest: String
    public var pdkDigest: String
    public var toolID: String
    public var toolDigest: String
    public var qualificationLevel: ToolQualificationLevel
    public var qualificationScope: ToolQualificationScope?
    public var disposition: SignoffEvidenceDisposition
    public var reason: String?

    public init(
        evidenceID: String,
        axis: ReleaseSignoffAxis,
        artifact: XcircuiteFileReference,
        designDigest: String,
        pdkDigest: String,
        toolID: String,
        toolDigest: String,
        qualificationLevel: ToolQualificationLevel,
        qualificationScope: ToolQualificationScope? = nil,
        disposition: SignoffEvidenceDisposition,
        reason: String? = nil
    ) {
        self.evidenceID = evidenceID
        self.axis = axis
        self.artifact = artifact
        self.designDigest = designDigest
        self.pdkDigest = pdkDigest
        self.toolID = toolID
        self.toolDigest = toolDigest
        self.qualificationLevel = qualificationLevel
        self.qualificationScope = qualificationScope
        self.disposition = disposition
        self.reason = reason
    }
}
