# ReleaseEngine

ReleaseEngine provides fail-closed signoff, tapeout packaging, and final release authorization for semiconductor design flows. It is usable as an independent Swift package and uses CircuiteFoundation artifacts as its public evidence boundary.

## Products

| Product | Responsibility |
|---|---|
| `ReleaseCore` | Signoff axes, canonical signoff bundle, exact multi-database release bundle construction, handoff manifest, and typed evidence references |
| `SignoffEngine` | Validate all production signoff axes, generate the canonical bundle, and persist/reload it immutably |
| `TapeoutEngine` | Generate immutable stream-out and foundry handoff artifacts, then validate stream-out/XOR evidence |
| `ReleaseEngine` | Authorize release from an independent human flow approval and independently reproducible tool trust |

Tool qualification is not performed by this package. ToolQualification owns trust evaluation; DesignFlowKernel owns human approval. `DefaultReleaseAuthorizer` consumes both inputs separately and fails closed if either cannot be reproduced.

## CLI

```text
release-engine profile --profile <digital|analog|mixed-signal>
release-engine signoff --request <path|->
release-engine tapeout --request <path|->
```

Exit code `0` means the requested operation completed, `2` means a typed blocked result, `3` means a typed failed result, and `4` means cancellation. Invalid commands, malformed arguments, and requests that cannot be decoded or executed exit with `1`.

## Release trust boundary

```text
canonical signoff bundle ─┐
human FlowApprovalRecord ─┼─> DefaultReleaseAuthorizer ─> authorized / blocked
ToolQualification inputs ─┘          │
                                     └─ re-reads raw retained artifacts
```

`DefaultReleaseExactBundleBuilder` is the owner of exact release inventory
derivation. It combines exact database revisions, the semantic dependency graph
digest, signoff content, approval evidence, qualification inputs and evidence,
and active revision-retention receipts. The builder validates the result before
returning it. `DefaultReleaseAuthorizer` uses the same
`ReleaseExactContentInventory` derivation and rejects approval or qualification
identity drift instead of trusting caller-assembled category lists.

```text
database revisions + semantic graph + signoff + approval + qualification + retention
                                      |
                                      v
                    DefaultReleaseExactBundleBuilder
                                      |
                                      v
                         validated ReleaseExactBundle
```

Authorization requires exact unique coverage of all release axes, including logic equivalence, RTL verification, DFT, and power intent, plus one reproducible production-eligible trust decision for every qualified producer scope retained by the bundle. Approval is authenticated against an attested canonical run ledger supplied by the owning persistence system: the retained human action and approval artifact must bind an immutable reviewed stage-result snapshot that contains the exact bundle. PEX, STA, and electrical evidence must name their requested operating corners, and every corner must be covered by both corpus and independent-oracle qualification evidence. No result, request, or bundle can approve itself. The standalone CLI does not expose authorization because it does not own the canonical run ledger; hosts inject `ReleaseApprovalLedgerReading` into `AttestedReleaseApprovalAuthenticator`.

Release-native results and artifacts retain the executing binary SHA-256,
semantic implementation version, invocation, and environment fingerprint.
Authorization and tapeout reject release evidence whose producer build identity
is absent or malformed.

Artifact content identity and materialization are separate contracts.
`ArtifactReference` carries location-independent content identity and descriptor
only; `ReleaseArtifactBinding` adds an explicitly resolved
`ArtifactAvailability`, and `ReleaseArtifactDestination` names a bounded output
location. Signoff and tapeout artifact persistence are protocol-first.
`ReleaseArtifactPersisting` creates an immutable artifact binding and reloads its
bytes after the write. `LocalReleaseArtifactStore` provides standalone
project-relative storage and reads through a root capability with bounded pages,
integrity receipts, and fallible close. Xcircuite can make its workspace store
conform directly to the same protocol to add ledger transactions.

Production tapeout requires `QualifiedGeometricXORExecutor`. Its configuration binds an externally qualified executable, the exact and unambiguous availability inventory for every qualification artifact, and a project-relative JSON report destination. The executor accepts only GDSII/OASIS layouts, copies verified executable and layout bytes into a private read-only execution workspace, invokes only those snapshots, and verifies them again after the process exits. It then persists the raw canonical report immutably and records execution provenance plus difference count and area. `LayoutXORResult` carries the exact qualification bindings into tapeout, where every retained artifact is read back before handoff. The foundry handoff retains the complete XOR qualification artifact graph, not only the raw comparison report. `DefaultLayoutXORComparator` is intentionally diagnostic-only: equal file bytes do not prove qualified geometric equivalence and never authorize tapeout.

## Build and integration

ReleaseEngine is an independent Swift package. Add the repository to a SwiftPM
package or Xcode project, then import only the product required by the caller.
Its package manifest pins the following public repositories for reproducible
standalone resolution:

| Dependency | Repository | Pinned revision |
|---|---|---|
| CircuiteFoundation | `https://github.com/1amageek/CircuiteFoundation.git` | `7abcac83517935c9b9f7553d7016d62cffde259d` |
| PDKKit | `https://github.com/1amageek/PDKKit.git` | `b62c5ad7e5819a24977038c2133856caed52f481` |
| ToolQualification | `https://github.com/1amageek/ToolQualification.git` | `d572d950a9dccb699413cd5157d901812354444f` |
| DesignFlowKernel | `https://github.com/1amageek/DesignFlowKernel.git` | `6bbe1a24bc7e0a983da747844d8b2db1c80fefd4` |
| PhysicalDesignEngine | `https://github.com/1amageek/PhysicalDesignEngine.git` | `a2b64a3f9f1651be0601496a7423a211c1438c49` |
| LogicDesign | `https://github.com/1amageek/LogicDesign.git` | `b9aa25b0b78e6168befa25df3bfe8309bd020a6d` |
| SignoffToolSupport | `https://github.com/1amageek/SignoffToolSupport.git` | `6bf675eecb27e3bd3440c5ce8a85c85c510fc3cb` |

Build the package and its test targets with `swift build --build-tests`. Tests cover human/agent approval separation, trust recomputation, strict persisted-result decoding, exact bundle inventory, bounded artifact access, immutable persistence, path containment, complete axis coverage, and qualification-to-handoff lineage.
