# ReleaseEngine

ReleaseEngine provides fail-closed signoff, tapeout packaging, and final release authorization for semiconductor design flows. It is usable as an independent Swift package and uses CircuiteFoundation artifacts as its public evidence boundary.

## Products

| Product | Responsibility |
|---|---|
| `ReleaseCore` | Signoff axes, canonical signoff bundle, handoff manifest, and typed evidence references |
| `SignoffEngine` | Validate all production signoff axes and reproduce the persisted canonical bundle |
| `TapeoutEngine` | Validate stream-out/XOR evidence and reproduce a foundry handoff artifact |
| `ReleaseEngine` | Authorize release from an independent human flow approval and independently reproducible tool trust |

Tool qualification is not performed by this package. ToolQualification owns trust evaluation; DesignFlowKernel owns human approval. `DefaultReleaseAuthorizer` consumes both inputs separately and fails closed if either cannot be reproduced.

## CLI

```text
release-engine profile --profile <digital|analog|mixed-signal>
release-engine signoff --request <path|->
release-engine tapeout --request <path|->
release-engine authorize --request <path|-> --project-root <path>
```

Exit code `0` means the requested operation completed, `2` means a typed blocked result, and `1` means the request could not be decoded or executed.

## Release trust boundary

```text
canonical signoff bundle ─┐
human FlowApprovalRecord ─┼─> DefaultReleaseAuthorizer ─> authorized / blocked
ToolQualification inputs ─┘          │
                                     └─ re-reads raw retained artifacts
```

Authorization requires exact unique coverage of all sixteen release axes, an approval bound to the exact bundle artifact, and one reproducible eligible trust decision for every required tool. No result or bundle can approve itself.

## Build and integration

`Package.swift` resolves every dependency independently. A sibling checkout is
used when its `Package.swift` exists; otherwise SwiftPM uses the pinned GitHub
revision. No umbrella repository is required to activate local dependencies.

| Dependency | Local sibling | Remote fallback revision |
|---|---|---|
| CircuiteFoundation | `../CircuiteFoundation` | `2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac` |
| PDKKit | `../PDKKit` | `aa145dfaa67454c44ac7767c37a28ab7f4b1d2e2` |
| ToolQualification | `../ToolQualification` | `32b031b5322f1ccb0ef78466faab0f895d47c4fd` |
| DesignFlowKernel | `../DesignFlowKernel` | `8b6c25876ae8f594ad1ac068cee6a156b6a1ad4b` |
| PhysicalDesignEngine | `../PhysicalDesignEngine` | `2a3f4215319b8515120f19a5bcb5627122663ff3` |
| LogicDesign | `../LogicDesign` | `8e0c8c2c63152aa45bf12d943fa034bb1aba0f1e` |

Use the workspace verifier or an Xcode package scheme with a timeout. Tests cover human/agent approval separation, trust recomputation, bundle integrity, and complete axis coverage.
