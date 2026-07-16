import CryptoKit
import Foundation
import ReleaseCore
import CircuiteFoundation

public struct CanonicalSignoffEvidenceDigester: SignoffEvidenceDigesting, Sendable {
    public init() {}

    public func digest(_ evidence: [ReleaseSignoffEvidenceReference]) throws -> String {
        let normalized = evidence
            .map(normalize)
            .sorted { $0.evidenceID < $1.evidenceID }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(normalized)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func normalize(
        _ evidence: ReleaseSignoffEvidenceReference
    ) -> ReleaseSignoffEvidenceReference {
        ReleaseSignoffEvidenceReference(
            evidenceID: evidence.evidenceID,
            axis: evidence.axis,
            artifact: evidence.artifact,
            designDigest: evidence.designDigest,
            pdkDigest: evidence.pdkDigest,
            toolID: evidence.toolID,
            toolVersion: evidence.toolVersion,
            toolBinaryDigest: evidence.toolBinaryDigest,
            inputArtifacts: evidence.inputArtifacts.sorted(by: artifactOrder),
            processQualification: evidence.processQualification,
            disposition: evidence.disposition,
            reason: evidence.reason
        )
    }

    private func artifactOrder(_ lhs: ArtifactReference, _ rhs: ArtifactReference) -> Bool {
        if lhs.id == rhs.id {
            return lhs.path < rhs.path
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }
}
