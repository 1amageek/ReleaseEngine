# ReleaseEngine Design

## Responsibility

ReleaseEngine turns immutable domain evidence into three distinct outputs: a signoff bundle, a tapeout handoff manifest, and a final authorization decision. It does not execute DRC/LVS/PEX/STA analyses and does not decide whether a tool is qualified.

## Trust ownership

| State | Owner |
|---|---|
| Domain findings and metrics | Producing engine |
| Tool trust | ToolQualification |
| Human approval and review binding | DesignFlowKernel |
| Canonical `.xcircuite` persistence | Xcircuite |
| Final release authorization | ReleaseEngine |

`DefaultReleaseAuthorizer` recomputes every supplied ToolQualification decision through a digest-verifying artifact reader. A status value without its descriptor, requirement, health input, and retained raw results is insufficient. Human approval is accepted only when it is an approved human `FlowApprovalRecord` bound to the exact signoff bundle artifact.

## Artifact invariants

- Signoff and handoff JSON must be canonical byte-for-byte.
- `ArtifactReference` digest and byte count are verified before decoding.
- Production signoff contains exactly one result for every `ReleaseSignoffAxis`.
- Missing, duplicate, failed, or blocked axes reject authorization.
- Bundle and handoff schemas contain no self-approval flag or approval digest.
- Tapeout accepts byte identity or retained production-qualified geometric XOR evidence.
