import CircuiteFoundation
import Foundation
import ReleaseCore

/// Native release-signoff result. The payload remains signoff-specific; no
/// package-wide result envelope is required.
public struct SignoffResult: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var status: ReleaseExecutionStatus
    public var diagnostics: [DesignDiagnostic]
    public var artifacts: [ArtifactReference]
    public var provenance: ExecutionProvenance
    public var payload: SignoffPayload

    public init(
        schemaVersion: Int,
        runID: String,
        status: ReleaseExecutionStatus,
        diagnostics: [DesignDiagnostic] = [],
        artifacts: [ArtifactReference] = [],
        metadata: ExecutionProvenance,
        payload: SignoffPayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.artifacts = artifacts
        self.provenance = metadata
        self.payload = payload
    }
}
