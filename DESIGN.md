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
- Signoff generates its bundle from validated typed evidence; callers provide only an immutable output locator, never precomputed bundle bytes.
- `ArtifactReference` digest and byte count are verified before decoding.
- Production signoff contains exactly one result for every `ReleaseSignoffAxis`.
- Missing, duplicate, failed, or blocked axes reject authorization.
- Bundle and handoff schemas contain no self-approval flag or approval digest.
- Tapeout accepts only retained evidence from a production-qualified geometric XOR process. Byte identity is diagnostic evidence and never satisfies the production gate.
- Digital and mixed-signal profiles require logic synthesis equivalence, RTL lint, CDC, RDC, formal proof, scan insertion, ATPG, BIST, and power-intent evidence.
- Each operational evidence record retains execution provenance. Its producer/supporting-tool identity, exact inputs, completion time, executable digest, and production qualification scope must agree.
- Native signoff evaluation, authorization, stream-out, and tapeout packaging
  identify their implementation with a semantic version plus the current
  executable SHA-256 and an environment fingerprint. Persisted release
  artifacts carry the same producer identity; missing or non-SHA build identity
  blocks downstream authorization and packaging.
- The bundle retains the exact operational evidence artifact inventory and complete production qualification scopes. Authorization rejects caller-selected trust inventories that differ from those scopes.
- The tapeout engine generates stream-out and handoff bytes before persistence; callers do not pre-construct release artifact references.
- `QualifiedGeometricXORExecutor` directly launches the executable retained by `ToolProcessQualificationEvidence`; it records the exact executable, arguments, working directory, sanitized environment digest, exit state, difference count/area, and raw report digest. ReleaseEngine consumes qualification evidence and never self-qualifies the tool.
- The foundry handoff schema embeds the complete typed `LayoutXORResult`; its manifest digest covers that result and its immutable report artifact.
- `ReleaseArtifactPersisting` must serialize conflicting writers, reject replacement, and reload exact bytes for verification.
- The default encoder only copies an already-standard GDSII or OASIS stream. Any format conversion requires a separately qualified `LayoutStreamEncoding` implementation.
