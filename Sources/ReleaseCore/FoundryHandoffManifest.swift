import Foundation
import CryptoKit
import CircuiteFoundation

public struct FoundryHandoffManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var releaseID: String
    public var foundryID: String
    public var signoffBundleArtifactDigest: String
    public var designDigest: String
    public var pdkDigest: String
    public var layoutDigest: String
    public var artifacts: [ArtifactReference]
    public var evidenceIDs: [String]
    public var generatedAt: Date
    public var manifestDigest: String

    public init(
        releaseID: String,
        foundryID: String,
        signoffBundleArtifactDigest: String,
        designDigest: String,
        pdkDigest: String,
        layoutDigest: String,
        artifacts: [ArtifactReference],
        evidenceIDs: [String],
        generatedAt: Date,
        manifestDigest: String,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.releaseID = releaseID
        self.foundryID = foundryID
        self.signoffBundleArtifactDigest = signoffBundleArtifactDigest
        self.designDigest = designDigest
        self.pdkDigest = pdkDigest
        self.layoutDigest = layoutDigest
        self.artifacts = artifacts.sorted { $0.id.rawValue < $1.id.rawValue }
        self.evidenceIDs = evidenceIDs.sorted()
        self.generatedAt = generatedAt
        self.manifestDigest = manifestDigest
    }

    public func computedManifestDigest() -> String {
        let artifactMaterial = artifacts
            .sorted { $0.path < $1.path }
            .map { [$0.path, $0.format.rawValue, $0.sha256, String($0.byteCount)].joined(separator: "|") }
            .joined(separator: "\n")
        let material = [
            String(schemaVersion),
            releaseID,
            foundryID,
            signoffBundleArtifactDigest,
            designDigest,
            pdkDigest,
            layoutDigest,
            artifactMaterial,
            evidenceIDs.sorted().joined(separator: ","),
            ISO8601DateFormatter().string(from: generatedAt),
        ].joined(separator: "\n")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public var isSelfConsistent: Bool {
        manifestDigest == computedManifestDigest()
    }

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decodeCanonical(from data: Data) throws -> FoundryHandoffManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(FoundryHandoffManifest.self, from: data)
        guard try manifest.canonicalData() == data else {
            throw FoundryHandoffManifestError.nonCanonicalEncoding
        }
        return manifest
    }
}
