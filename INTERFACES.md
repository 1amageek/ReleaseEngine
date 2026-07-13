# ReleaseEngine Interface Contract

## Common shape

```swift
public protocol DomainExecuting: Sendable {
    func execute(
        _ request: DomainRequest
    ) async throws -> DomainResult
}
```

Requests carry a schema version, run ID and typed artifact references. Payloads contain domain metrics only. Diagnostics and artifacts belong to the shared envelope.

## Products

### ReleaseCore

Signoff and tapeout references.

### SignoffEngine

Required-axis applicability and verdict.

### TapeoutEngine

Stream-out validation and foundry handoff.

### ReleaseEngine

Umbrella API.


## Error contract

- Throw only when execution cannot produce a valid result envelope.
- Represent design findings and failed checks as typed diagnostics and a completed domain payload.
- Represent missing prerequisites or insufficient semantics as `blocked`.
- Preserve cancellation as `cancelled`.
- Do not swallow parser, process or persistence failures.

## Composition

Xcircuite invokes these protocols directly and persists returned
`ArtifactReference` values in its workspace store. DesignFlowKernel owns flow
status, approval and resume; ToolQualification owns capability and trust
decisions. Engines only return domain results, diagnostics and provenance.
