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

## Development

Use the workspace verifier or an Xcode package scheme with a timeout. Tests cover human/agent approval separation, trust recomputation, bundle integrity, and complete axis coverage.
