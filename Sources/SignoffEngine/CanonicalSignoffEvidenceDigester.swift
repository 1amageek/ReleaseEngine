import CryptoKit
import Foundation
import ReleaseCore
import CircuiteFoundation

public struct CanonicalSignoffEvidenceDigester: SignoffEvidenceDigesting, Sendable {
    public init() {}

    public func digest(_ evidence: [ReleaseSignoffEvidenceReference]) throws -> String {
        let normalized = try evidence
            .map { try normalize($0) }
            .sorted { $0.evidenceID < $1.evidenceID }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(normalized)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func normalize(
        _ evidence: ReleaseSignoffEvidenceReference
    ) throws -> ReleaseSignoffEvidenceReference {
        let sourceProvenance = evidence.executionProvenance
        let normalizedProvenance = try ExecutionProvenance(
            producer: sourceProvenance.producer,
            supportingTools: sourceProvenance.supportingTools.sorted(by: producerOrder),
            inputs: sourceProvenance.inputs.sorted(by: artifactOrder),
            invocation: sourceProvenance.invocation,
            environment: sourceProvenance.environment,
            configurationDigest: sourceProvenance.configurationDigest,
            inputDesignRevision: sourceProvenance.inputDesignRevision,
            outputDesignRevision: sourceProvenance.outputDesignRevision,
            randomSeed: sourceProvenance.randomSeed,
            startedAt: sourceProvenance.startedAt,
            completedAt: sourceProvenance.completedAt
        )
        return ReleaseSignoffEvidenceReference(
            evidenceID: evidence.evidenceID,
            axis: evidence.axis,
            artifact: evidence.artifact,
            designDigest: evidence.designDigest,
            pdkDigest: evidence.pdkDigest,
            toolID: evidence.toolID,
            toolVersion: evidence.toolVersion,
            toolBinaryDigest: evidence.toolBinaryDigest,
            inputArtifacts: evidence.inputArtifacts.sorted(by: artifactOrder),
            executionProvenance: normalizedProvenance,
            processQualification: evidence.processQualification,
            disposition: evidence.disposition,
            reason: evidence.reason
        )
    }

    private func producerOrder(_ lhs: ProducerIdentity, _ rhs: ProducerIdentity) -> Bool {
        [lhs.kind.rawValue, lhs.identifier, lhs.version, lhs.build ?? ""]
            .lexicographicallyPrecedes(
                [rhs.kind.rawValue, rhs.identifier, rhs.version, rhs.build ?? ""]
            )
    }

    private func artifactOrder(_ lhs: ArtifactReference, _ rhs: ArtifactReference) -> Bool {
        let lhsKey = [
            lhs.id.description,
            lhs.descriptor.role.rawValue,
            lhs.descriptor.kind.rawValue,
            lhs.descriptor.format.rawValue,
            lhs.digest.algorithm.rawValue,
            lhs.digest.hexadecimalValue,
            String(lhs.byteCount),
        ]
        let rhsKey = [
            rhs.id.description,
            rhs.descriptor.role.rawValue,
            rhs.descriptor.kind.rawValue,
            rhs.descriptor.format.rawValue,
            rhs.digest.algorithm.rawValue,
            rhs.digest.hexadecimalValue,
            String(rhs.byteCount),
        ]
        return lhsKey.lexicographicallyPrecedes(rhsKey)
    }
}
