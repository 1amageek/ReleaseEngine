import Foundation
import ToolQualification
import CircuiteFoundation

public struct ReleaseSignoffAxisRequirement: Sendable, Hashable, Codable {
    public var axis: ReleaseSignoffAxis
    public var required: Bool
    public var minimumEvidenceCount: Int
    public var minimumQualificationLevel: ToolQualificationLevel
    public var requiredArtifactKinds: [ArtifactKind]

    public init(
        axis: ReleaseSignoffAxis,
        required: Bool,
        minimumEvidenceCount: Int = 1,
        minimumQualificationLevel: ToolQualificationLevel = .smokeChecked,
        requiredArtifactKinds: [ArtifactKind] = [.report]
    ) {
        self.axis = axis
        self.required = required
        self.minimumEvidenceCount = minimumEvidenceCount
        self.minimumQualificationLevel = minimumQualificationLevel
        self.requiredArtifactKinds = requiredArtifactKinds
    }
}
