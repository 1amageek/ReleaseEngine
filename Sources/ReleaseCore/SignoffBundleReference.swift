import Foundation
import XcircuitePackage

public struct SignoffBundleReference: Sendable, Hashable, Codable {
    public var artifact: XcircuiteFileReference
    public var designDigest: String
    public var pdkDigest: String
    public var finalLayoutDigest: String?
    public var bundleDigest: String?
    public var approved: Bool

    public init(
        artifact: XcircuiteFileReference,
        designDigest: String,
        pdkDigest: String,
        finalLayoutDigest: String? = nil,
        bundleDigest: String? = nil,
        approved: Bool = false
    ) {
        self.artifact = artifact
        self.designDigest = designDigest
        self.pdkDigest = pdkDigest
        self.finalLayoutDigest = finalLayoutDigest
        self.bundleDigest = bundleDigest
        self.approved = approved
    }
}
