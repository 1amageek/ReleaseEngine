import CircuiteFoundation
import Foundation
import ReleaseCore

public struct ReleaseAuthorizationResult: Sendable, Hashable, Codable, ArtifactProducing,
    DiagnosticReporting, EvidenceProviding
{
    public let status: ReleaseAuthorizationStatus
    public let signoffBundle: SignoffBundleReference?
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest

    public init(
        status: ReleaseAuthorizationStatus,
        signoffBundle: SignoffBundleReference?,
        diagnostics: [DesignDiagnostic],
        provenance: ExecutionProvenance
    ) {
        self.status = status
        self.signoffBundle = signoffBundle
        self.artifacts = signoffBundle.map { [$0.artifact] } ?? []
        self.diagnostics = diagnostics
        self.evidence = EvidenceManifest(provenance: provenance, artifacts: artifacts)
    }
}
