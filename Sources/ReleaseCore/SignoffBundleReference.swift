import Foundation
import LogicIR
import CircuiteFoundation

public struct SignoffBundleReference: Sendable, Hashable, Codable {
    public var artifact: ReleaseArtifactBinding
    public var designDigest: String
    public var designProvenance: LogicDesignProvenance?
    public var pdkDigest: String
    public var finalLayoutDigest: String?

    public init(
        artifact: ReleaseArtifactBinding,
        designDigest: String,
        designProvenance: LogicDesignProvenance? = nil,
        pdkDigest: String,
        finalLayoutDigest: String? = nil
    ) {
        self.artifact = artifact
        self.designDigest = designDigest.lowercased()
        self.designProvenance = designProvenance
        self.pdkDigest = pdkDigest.lowercased()
        self.finalLayoutDigest = finalLayoutDigest?.lowercased()
    }
}
