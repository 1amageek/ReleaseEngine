import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignFlowKernel
import Foundation

public struct ReleaseAuthorizationResult: Sendable, Hashable, Codable, ArtifactProducing,
    DiagnosticReporting, EvidenceProviding
{
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let status: ReleaseAuthorizationStatus
    public let signoffBundle: SignoffBundleReference?
    public let exactReleaseBundle: ReleaseExactBundle?
    public let approval: FlowApprovalRecord
    public let artifactBindings: [ReleaseArtifactBinding]
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case status
        case signoffBundle
        case exactReleaseBundle
        case approval
        case artifactBindings
        case diagnostics
        case evidence
    }

    public init(
        status: ReleaseAuthorizationStatus,
        signoffBundle: SignoffBundleReference?,
        exactReleaseBundle: ReleaseExactBundle?,
        approval: FlowApprovalRecord,
        diagnostics: [DesignDiagnostic],
        provenance: ExecutionProvenance
    ) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.status = status
        self.signoffBundle = signoffBundle
        self.exactReleaseBundle = exactReleaseBundle
        self.approval = approval
        let artifactBindings = signoffBundle.map { [$0.artifact] } ?? []
        self.artifactBindings = artifactBindings
        self.diagnostics = diagnostics
        self.evidence = try EvidenceManifest.contentAddressed(
            provenance: provenance,
            artifacts: artifactBindings.map(\.reference),
            digester: SHA256ContentDigester()
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = Self(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            status: try container.decode(
                ReleaseAuthorizationStatus.self,
                forKey: .status
            ),
            signoffBundle: try container.decodeIfPresent(
                SignoffBundleReference.self,
                forKey: .signoffBundle
            ),
            exactReleaseBundle: try container.decodeIfPresent(
                ReleaseExactBundle.self,
                forKey: .exactReleaseBundle
            ),
            approval: try container.decode(
                FlowApprovalRecord.self,
                forKey: .approval
            ),
            artifactBindings: try container.decode(
                [ReleaseArtifactBinding].self,
                forKey: .artifactBindings
            ),
            diagnostics: try container.decode(
                [DesignDiagnostic].self,
                forKey: .diagnostics
            ),
            evidence: try container.decode(
                EvidenceManifest.self,
                forKey: .evidence
            )
        )
        try decoded.validateDecodedContract()
        self = decoded
    }

    private init(
        schemaVersion: Int,
        status: ReleaseAuthorizationStatus,
        signoffBundle: SignoffBundleReference?,
        exactReleaseBundle: ReleaseExactBundle?,
        approval: FlowApprovalRecord,
        artifactBindings: [ReleaseArtifactBinding],
        diagnostics: [DesignDiagnostic],
        evidence: EvidenceManifest
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.signoffBundle = signoffBundle
        self.exactReleaseBundle = exactReleaseBundle
        self.approval = approval
        self.artifactBindings = artifactBindings
        self.diagnostics = diagnostics
        self.evidence = evidence
    }

    private func validateDecodedContract() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ReleaseAuthorizationResultValidationError.unsupportedSchemaVersion(
                actual: schemaVersion,
                expected: Self.currentSchemaVersion
            )
        }
        let hasError = diagnostics.contains { $0.severity == .error }
        switch status {
        case .authorized:
            guard let signoffBundle, exactReleaseBundle != nil else {
                throw ReleaseAuthorizationResultValidationError.authorizedPayloadMissing
            }
            guard approval.verdict == .approved,
                  approval.reviewerKind == .human,
                  !approval.reviewer.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty,
                  approval.evidence.stageResult.reference
                    == signoffBundle.artifact.reference else {
                throw ReleaseAuthorizationResultValidationError.authorizedApprovalInvalid
            }
            guard !hasError else {
                throw ReleaseAuthorizationResultValidationError
                    .authorizedDiagnosticsContainError
            }
            guard artifactBindings == [signoffBundle.artifact] else {
                throw ReleaseAuthorizationResultValidationError.artifactBindingMismatch
            }
            let requiredInputs = [
                signoffBundle.artifact.reference,
                approval.evidence.plan.reference,
                approval.evidence.stageResult.reference,
            ]
            guard requiredInputs.allSatisfy(
                evidence.provenance.inputs.contains
            ) else {
                throw ReleaseAuthorizationResultValidationError
                    .authorizedProvenanceIncomplete
            }
        case .blocked:
            guard signoffBundle == nil,
                  exactReleaseBundle == nil,
                  artifactBindings.isEmpty else {
                throw ReleaseAuthorizationResultValidationError.blockedPayloadPresent
            }
            guard hasError else {
                throw ReleaseAuthorizationResultValidationError.blockedDiagnosticMissing
            }
        }

        let expectedEvidence = try EvidenceManifest.contentAddressed(
            schemaVersion: evidence.schemaVersion,
            provenance: evidence.provenance,
            artifacts: artifactBindings.map(\.reference),
            digester: SHA256ContentDigester()
        )
        guard evidence == expectedEvidence else {
            throw ReleaseAuthorizationResultValidationError.evidenceManifestMismatch
        }
    }
}
