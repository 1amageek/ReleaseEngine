public enum ReleaseAuthorizationResultValidationError:
    Error,
    Sendable,
    Hashable
{
    case unsupportedSchemaVersion(actual: Int, expected: Int)
    case authorizedPayloadMissing
    case authorizedApprovalInvalid
    case authorizedDiagnosticsContainError
    case authorizedProvenanceIncomplete
    case blockedPayloadPresent
    case blockedDiagnosticMissing
    case artifactBindingMismatch
    case evidenceManifestMismatch
}
