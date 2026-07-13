import Foundation
import LogicIR
import CircuiteFoundation

public struct SignoffBundleReference: Sendable, Hashable, Codable {
    public var artifact: ArtifactReference
    public var designDigest: String
    public var designProvenance: LogicDesignProvenance?
    public var pdkDigest: String
    public var finalLayoutDigest: String?
    public var bundleDigest: String?
    public var approved: Bool

    public init(
        artifact: ArtifactReference,
        designDigest: String,
        designProvenance: LogicDesignProvenance? = nil,
        pdkDigest: String,
        finalLayoutDigest: String? = nil,
        bundleDigest: String? = nil,
        approved: Bool = false
    ) {
        self.artifact = artifact
        self.designDigest = designDigest
        self.designProvenance = designProvenance
        self.pdkDigest = pdkDigest
        self.finalLayoutDigest = finalLayoutDigest
        self.bundleDigest = bundleDigest
        self.approved = approved
    }
}
