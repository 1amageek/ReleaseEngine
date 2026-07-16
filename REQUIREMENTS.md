# ReleaseEngine Requirements

## Goal

Permit tapeout only when an immutable design has complete, applicable evidence and independently supplied tool-trust decisions.

## Required functions

| Function | Required behavior | Priority |
|---|---|---:|
| Signoff profile | Define required axes and evidence-acceptance rules for digital, analog and mixed-signal designs. | P0 |
| Applicability resolution | Represent passed, failed, blocked and profile-approved not-applicable states. | P0 |
| Evidence validation | Verify artifact integrity, design/PDK/tool digests and cross-axis revision consistency. | P0 |
| Waiver governance | Persist scoped waivers, authority, rationale, expiry and affected evidence. | P0 |
| Signoff bundle | Produce an immutable, machine-verifiable technical-pass or blocked evidence packet. | P0 |
| Stream-out validation | Validate top cell, units, layer map, hierarchy and GDS/OASIS generation. | P1 |
| XOR and release checks | Compare source and streamed layout and verify seal, pad and release requirements. | P1 |
| Foundry handoff | Package checksums, manifests, evidence, waivers and final layout artifacts. | P1 |

## Required outcomes

- No required axis can be silently omitted.
- Tapeout accepts only a completed, verified SignoffBundle bound to the same final layout.
- Release artifacts are independently reproducible and auditable.

## Common platform requirements

- Public execution surfaces are protocol-first, Sendable and dependency-injected.
- Requests and payloads are Codable, Hashable and schema-versioned.
- Inputs and outputs use immutable Foundation `ArtifactReference` artifacts.
- Diagnostics contain a stable code, severity, affected entity and suggested actions.
- Unsupported semantics and missing prerequisites produce blocked results.
- Native and external-tool backends conform to identical request and payload schemas.
- Execution capability, corpus validation, oracle correlation, process qualification and release approval remain distinct.
- Xcircuite owns concrete artifact persistence and composition; DesignFlowKernel owns flow construction, policy gates, approval and resume.
- The package never imports Xcircuite or circuit-studio.

## Required developer surfaces

- Typed API
- Deterministic JSON CLI
- Positive and negative fixtures
- Contract and parser round-trip tests
- Generated positive and negative integrity fixtures
- Capability and limitation report
- Xcircuite stage composition tests using direct protocol conformance
