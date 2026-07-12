import Foundation
import XcircuitePackage

public struct FoundryHandoffManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var releaseID: String
    public var foundryID: String
    public var signoffBundleDigest: String
    public var designDigest: String
    public var pdkDigest: String
    public var layoutDigest: String
    public var artifacts: [XcircuiteFileReference]
    public var evidenceIDs: [String]
    public var generatedAt: Date
    public var manifestDigest: String

    public init(
        releaseID: String,
        foundryID: String,
        signoffBundleDigest: String,
        designDigest: String,
        pdkDigest: String,
        layoutDigest: String,
        artifacts: [XcircuiteFileReference],
        evidenceIDs: [String],
        generatedAt: Date,
        manifestDigest: String,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.releaseID = releaseID
        self.foundryID = foundryID
        self.signoffBundleDigest = signoffBundleDigest
        self.designDigest = designDigest
        self.pdkDigest = pdkDigest
        self.layoutDigest = layoutDigest
        self.artifacts = artifacts
        self.evidenceIDs = evidenceIDs
        self.generatedAt = generatedAt
        self.manifestDigest = manifestDigest
    }

    public func computedManifestDigest() -> String {
        let artifactMaterial = artifacts
            .sorted { $0.path < $1.path }
            .map { [$0.path, $0.format.rawValue, $0.sha256 ?? "", String($0.byteCount ?? -1)].joined(separator: "|") }
            .joined(separator: "\n")
        let material = [
            String(schemaVersion),
            releaseID,
            foundryID,
            signoffBundleDigest,
            designDigest,
            pdkDigest,
            layoutDigest,
            artifactMaterial,
            evidenceIDs.sorted().joined(separator: ","),
            ISO8601DateFormatter().string(from: generatedAt),
        ].joined(separator: "\n")
        return XcircuiteHasher().sha256(data: Data(material.utf8))
    }

    public var isSelfConsistent: Bool {
        manifestDigest == computedManifestDigest()
    }
}
