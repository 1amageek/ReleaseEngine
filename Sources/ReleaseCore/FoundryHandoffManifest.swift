import Foundation
import CryptoKit
import CircuiteFoundation

public struct FoundryHandoffManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 5

    public var schemaVersion: Int
    public var releaseID: String
    public var foundryID: String
    public var signoffBundleArtifactDigest: String
    public var designDigest: String
    public var pdkDigest: String
    public var layoutDigest: String
    public var artifacts: [ArtifactReference]
    public var evidenceIDs: [String]
    public var layoutXORResult: LayoutXORResult
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
        layoutXORResult: LayoutXORResult,
        generatedAt: Date,
        manifestDigest: String,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.releaseID = releaseID
        self.foundryID = foundryID
        self.signoffBundleArtifactDigest = signoffBundleArtifactDigest.lowercased()
        self.designDigest = designDigest.lowercased()
        self.pdkDigest = pdkDigest.lowercased()
        self.layoutDigest = layoutDigest.lowercased()
        self.artifacts = artifacts.sorted(by: Self.artifactSort)
        self.evidenceIDs = evidenceIDs.sorted()
        self.layoutXORResult = layoutXORResult
        self.generatedAt = Date(
            timeIntervalSince1970: generatedAt.timeIntervalSince1970.rounded(.down)
        )
        self.manifestDigest = manifestDigest.lowercased()
    }

    public func computedManifestDigest() throws -> String {
        let artifactEntries = artifacts
            .sorted(by: Self.artifactSort)
            .map {
                Self.lengthPrefixed([
                    $0.id.description,
                    $0.descriptor.role.rawValue,
                    $0.descriptor.kind.rawValue,
                    $0.descriptor.format.rawValue,
                    $0.digest.algorithm.rawValue,
                    $0.digest.hexadecimalValue,
                    String($0.byteCount),
                ])
            }
        let artifactMaterial = Self.lengthPrefixed(artifactEntries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let layoutXORMaterial = try encoder.encode(layoutXORResult).base64EncodedString()
        let material = Self.lengthPrefixed([
            String(schemaVersion),
            releaseID,
            foundryID,
            signoffBundleArtifactDigest,
            designDigest,
            pdkDigest,
            layoutDigest,
            artifactMaterial,
            Self.lengthPrefixed(evidenceIDs.sorted()),
            layoutXORMaterial,
            ISO8601DateFormatter().string(from: generatedAt),
        ])
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public var isSelfConsistent: Bool {
        let expectedDigest: String
        do {
            expectedDigest = try computedManifestDigest()
        } catch {
            return false
        }
        return schemaVersion == Self.currentSchemaVersion
            && Self.isToken(releaseID)
            && Self.isToken(foundryID)
            && Self.isSHA256(signoffBundleArtifactDigest)
            && Self.isSHA256(designDigest)
            && Self.isSHA256(pdkDigest)
            && Self.isSHA256(layoutDigest)
            && Self.isSHA256(manifestDigest)
            && generatedAt.timeIntervalSinceReferenceDate.isFinite
            && !artifacts.isEmpty
            && artifacts.count == Set(artifacts).count
            && artifacts.allSatisfy {
                $0.digest.algorithm == .sha256
                    && $0.byteCount > 0
            }
            && !evidenceIDs.isEmpty
            && evidenceIDs.count == Set(evidenceIDs).count
            && evidenceIDs.allSatisfy(Self.isToken)
            && layoutXORResult.isTapeoutQualified(at: generatedAt)
            && layoutXORResult.evidenceArtifact.map(artifacts.contains) == true
            && manifestDigest.caseInsensitiveCompare(expectedDigest) == .orderedSame
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
        guard manifest.schemaVersion == currentSchemaVersion else {
            throw FoundryHandoffManifestError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        let normalized = FoundryHandoffManifest(
            releaseID: manifest.releaseID,
            foundryID: manifest.foundryID,
            signoffBundleArtifactDigest: manifest.signoffBundleArtifactDigest,
            designDigest: manifest.designDigest,
            pdkDigest: manifest.pdkDigest,
            layoutDigest: manifest.layoutDigest,
            artifacts: manifest.artifacts,
            evidenceIDs: manifest.evidenceIDs,
            layoutXORResult: manifest.layoutXORResult,
            generatedAt: manifest.generatedAt,
            manifestDigest: manifest.manifestDigest,
            schemaVersion: manifest.schemaVersion
        )
        guard normalized == manifest,
              normalized.isSelfConsistent else {
            throw FoundryHandoffManifestError.invalidContent
        }
        guard try normalized.canonicalData() == data else {
            throw FoundryHandoffManifestError.nonCanonicalEncoding
        }
        return normalized
    }

    private static func artifactSort(
        _ lhs: ArtifactReference,
        _ rhs: ArtifactReference
    ) -> Bool {
        let lhsKey = artifactKey(lhs)
        let rhsKey = artifactKey(rhs)
        return lhsKey.lexicographicallyPrecedes(rhsKey)
    }

    private static func artifactKey(_ artifact: ArtifactReference) -> [String] {
        [
            artifact.id.description,
            artifact.descriptor.role.rawValue,
            artifact.descriptor.kind.rawValue,
            artifact.descriptor.format.rawValue,
            artifact.digest.algorithm.rawValue,
            artifact.digest.hexadecimalValue,
            String(artifact.byteCount),
        ]
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }

    private static func isToken(_ value: String) -> Bool {
        !value.isEmpty
            && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
            && !value.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }

    private static func lengthPrefixed(_ values: [String]) -> String {
        values.map { "\($0.utf8.count):\($0)" }.joined()
    }
}
