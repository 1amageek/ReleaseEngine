# ReleaseEngine Interface Contract

## Signoff

`SignoffEvaluating.execute(_:)` validates typed evidence for every required axis, generates canonical `SignoffBundle` bytes, creates the artifact through `ReleaseArtifactPersisting`, reloads the exact bytes, and returns the verified binding. `SignoffRequest` carries a project-relative `ReleaseArtifactDestination` and never accepts precomputed bundle content or a precomputed reference. A successful result means the technical signoff checks passed; it is not human approval.

Each `ReleaseSignoffEvidenceReference` binds its operational result to an `ExecutionProvenance`, exact design/PDK inputs, and one independently qualified production scope. Qualification corpus outputs are not operational signoff outputs; the operational artifact is linked through its producer and execution provenance instead.

## Tapeout

`TapeoutPackaging.execute(_:)` generates a canonical standard stream and foundry handoff manifest, persists both through `ReleaseArtifactPersisting`, reloads their exact bytes, and verifies the signoff bundle, PDK, final layout, stream-out, and XOR result. It returns a completed or blocked packaging result and does not authorize release.

`TapeoutRequest` carries `StreamOutGenerationRequest` and two immutable artifact locations: the stream output and handoff output. It does not accept pre-persisted stream or handoff references. `LayoutStreamEncoding` owns stream byte generation. The default implementation preserves the exact bytes of an existing GDSII or OASIS source and blocks format conversion; a production format converter must directly conform to that protocol and carry its own qualification evidence.

`LayoutXORComparing.compare(source:streamed:pdkDigest:projectRoot:)` is asynchronous. `DefaultLayoutXORComparator` performs byte-identity diagnostics only and cannot authorize tapeout. Production callers provide `QualifiedGeometricXORExecutor` with `GeometricXORToolConfiguration`, externally issued `ToolProcessQualificationEvidence`, exactly one non-conflicting binding for every qualification artifact, and an immutable JSON report destination. After verifying the caller-owned executable and layouts, the executor copies their exact bytes into a private execution workspace and invokes only those snapshots with `--source-layout`, `--streamed-layout`, and `--report`; no shell or fallback comparator is used. It verifies every snapshot again after execution and fails closed if the tool changed an input or its own executable. A zero exit code, canonical report, zero difference count, zero difference area, exact executable identity, matching PDK scope, retained report digest, complete qualification bindings, and complete execution provenance are all required. The result carries those bindings into tapeout read-back and handoff retention.

`ReleaseArtifactPersisting` is the shared signoff/tapeout storage boundary in `ReleaseCore`. Implementations must create rather than replace, serialize conflicting writers, return a binding derived from persisted bytes, and reload those bytes. ReleaseEngine verifies the returned availability, SHA-256 digest, byte count, canonical encoding, and decoded content before reporting completion. `LocalReleaseArtifactStore` reads through bounded root-capability sessions and reports budget, integrity, cancellation, and cleanup failures as typed errors.

## Authorization

```swift
public protocol ReleaseAuthorizing: Engine
where Request == ReleaseAuthorizationRequest,
      Output == ReleaseAuthorizationResult {}
```

`ReleaseAuthorizationRequest` carries:

- the canonical signoff bundle reference;
- the validated exact release bundle containing exact database revisions, semantic dependency graph, content identities, and active retention receipts;
- one human `FlowApprovalRecord` whose canonical ledger action and immutable reviewed stage-result snapshot bind that exact artifact;
- exact approval and qualification record artifact bindings plus explicitly classified additional content identities;
- required tool identifiers;
- ToolQualification request/decision pairs that can be independently recomputed;
- a fixed evaluation time.

Artifact access, approval authentication, and ToolQualification execution are injected into the authorizer. `AttestedReleaseApprovalAuthenticator` verifies the approval artifact, human review action, plan, reviewed stage result, and exact signoff bundle binding from a ledger supplied through `ReleaseApprovalLedgerReading`. The owning persistence system must complete transaction recovery, canonical projection validation, decision-projection validation, and retained-artifact attestation before returning that ledger. ReleaseEngine does not interpret `.xcircuite` paths. The reviewed stage-result reference remains an explicit authorization provenance input even when the signoff bundle is retained as a separate artifact.

The output status is `.authorized` only when approval, production trust, retained evidence integrity, canonical bytes, release bindings, exact signoff-axis coverage, and the bundle's complete qualification-scope inventory all pass. Caller-provided content, approval, qualification, required tool, decision, and qualification-request inventories must exactly equal their owner-derived sets. Otherwise it is `.blocked` with structured diagnostics. A decoded persisted authorization is usable only after its schema, status/payload, approval binding, artifact projection, provenance, diagnostics, and evidence manifest are revalidated.

## Composition

Xcircuite persists Foundation artifacts and invokes these protocols directly. Its workspace store should conform directly to `ReleaseArtifactPersisting`; no adapter layer is required. DesignFlowKernel controls run lifecycle and approval. ToolQualification owns trust. ReleaseEngine does not import Xcircuite or UI state.
