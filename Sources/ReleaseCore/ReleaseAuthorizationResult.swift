import CircuiteFoundation
import DesignFlowKernel
import Foundation

public struct ReleaseAuthorizationResult: Sendable, Hashable, Codable, ArtifactProducing,
    DiagnosticReporting, EvidenceProviding
{
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let status: ReleaseAuthorizationStatus
    public let signoffBundle: SignoffBundleReference?
    public let approval: FlowApprovalRecord
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest

    public init(
        status: ReleaseAuthorizationStatus,
        signoffBundle: SignoffBundleReference?,
        approval: FlowApprovalRecord,
        diagnostics: [DesignDiagnostic],
        provenance: ExecutionProvenance
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.status = status
        self.signoffBundle = signoffBundle
        self.approval = approval
        self.artifacts = signoffBundle.map { [$0.artifact] } ?? []
        self.diagnostics = diagnostics
        self.evidence = EvidenceManifest(provenance: provenance, artifacts: artifacts)
    }
}
