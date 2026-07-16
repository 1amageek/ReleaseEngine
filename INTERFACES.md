# ReleaseEngine Interface Contract

## Signoff

`SignoffEvaluating.execute(_:)` validates typed evidence for every required axis and compares the computed `SignoffBundle` with a pre-persisted canonical artifact. A successful result means the technical signoff checks passed; it is not human approval.

## Tapeout

`TapeoutPackaging.execute(_:)` verifies the signoff bundle, PDK, final layout, stream-out, XOR result, and handoff artifact. It returns a completed or blocked packaging result and does not authorize release.

## Authorization

```swift
public protocol ReleaseAuthorizing: Engine
where Request == ReleaseAuthorizationRequest,
      Output == ReleaseAuthorizationResult {}
```

`ReleaseAuthorizationRequest` carries:

- the canonical signoff bundle reference;
- one human `FlowApprovalRecord` bound to that exact artifact;
- required tool identifiers;
- ToolQualification request/decision pairs that can be independently recomputed;
- a fixed evaluation time.

Artifact access and ToolQualification execution are injected into the authorizer. The request contains no filesystem path or concrete storage dependency.

The output status is `.authorized` only when approval, trust, artifact integrity, canonical bytes, release bindings, and exact signoff-axis coverage all pass. Otherwise it is `.blocked` with structured diagnostics.

## Composition

Xcircuite persists Foundation artifacts and invokes these protocols directly. DesignFlowKernel controls run lifecycle and approval. ToolQualification owns trust. ReleaseEngine does not import Xcircuite or UI state.
