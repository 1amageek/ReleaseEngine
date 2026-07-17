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

`Package.swift` resolves every dependency independently. Inside the LSI
workspace identified by `../docs/workspace-packages.json`, an available sibling
checkout is used. Outside that workspace, SwiftPM uses the pinned GitHub
revision, so ReleaseEngine builds as an independent repository.

| Dependency | Local sibling | Remote fallback revision |
|---|---|---|
| CircuiteFoundation | `../CircuiteFoundation` | `2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac` |
| PDKKit | `../PDKKit` | `28f3b83304ad2bbb0c2e0269d26616081d90d992` |
| ToolQualification | `../ToolQualification` | `f6cacdbf64038a35ab62d70f575a8dd8349e5604` |
| DesignFlowKernel | `../DesignFlowKernel` | `68e247274e34e56b1337df125b74480196209901` |
| PhysicalDesignEngine | `../PhysicalDesignEngine` | `a98c0895c0c0340326f79d7838ddc37ba86cfa2b` |
| LogicDesign | `../LogicDesign` | `09768ed203d97d1d0f79f786f9988fcb2cd39155` |

Use the workspace verifier or an Xcode package scheme with a timeout. Tests cover human/agent approval separation, trust recomputation, bundle integrity, and complete axis coverage.
