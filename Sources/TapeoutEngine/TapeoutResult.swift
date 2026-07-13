import CircuiteFoundation
import Foundation
import ReleaseCore

/// Native tapeout packaging result with a tapeout-specific payload.
public struct TapeoutResult: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var status: ReleaseExecutionStatus
    public var diagnostics: [DesignDiagnostic]
    public var artifacts: [ArtifactReference]
    public var provenance: ExecutionProvenance
    public var payload: TapeoutPayload

    public init(
        schemaVersion: Int,
        runID: String,
        status: ReleaseExecutionStatus,
        diagnostics: [DesignDiagnostic] = [],
        artifacts: [ArtifactReference] = [],
        metadata: ExecutionProvenance,
        payload: TapeoutPayload
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
