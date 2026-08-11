# ReleaseEngine Requirements

## Goal

Permit tapeout only when an immutable design has complete, applicable evidence and independently supplied tool-trust decisions.

## Required functions

| Function | Required behavior | Priority |
|---|---|---:|
| Signoff profile | Define required axes and evidence-acceptance rules for digital, analog and mixed-signal designs. | P0 |
| Applicability resolution | Represent passed, failed, blocked and profile-approved not-applicable states. | P0 |
| Evidence validation | Verify artifact integrity, operational execution provenance, exact design/PDK/tool identity, completion time and cross-axis revision consistency. | P0 |
| Waiver governance | Persist scoped waivers, authority, rationale, expiry and affected evidence. | P0 |
| Signoff bundle | Generate, immutably persist and reload a canonical technical-pass packet containing exact evidence artifacts and production qualification scopes. | P0 |
| Stream-out generation | Generate and immutably persist GDSII/OASIS bytes, then validate top cell, units, layer map and hierarchy. | P0 |
| Qualified geometric XOR | Run an independently qualified geometric comparator over source and streamed standard layouts; retain exact invocation provenance, difference count/area, and raw report digest. Any difference, unqualified scope, timeout, cancellation, launch/exit failure, malformed report, or artifact-integrity failure blocks or fails tapeout. | P0 |
| Foundry handoff | Generate canonical checksums and manifests, persist immutably, reload, and verify exact bytes. | P0 |

## Required outcomes

- No required axis can be silently omitted.
- Tapeout accepts only a completed, verified SignoffBundle bound to the same final layout.
- Release artifacts are independently reproducible and auditable.
- Release authorization accepts only production qualification requests whose exact scopes equal the producer scopes retained by the signoff bundle.
- Digital and mixed-signal release profiles require logic equivalence, RTL lint, CDC, RDC, formal proof, scan, ATPG, BIST and power-intent evidence.

## Common platform requirements

- Public execution surfaces are protocol-first, Sendable and dependency-injected.
- Requests and payloads are Codable, Hashable and schema-versioned.
- Inputs and outputs use immutable CircuiteFoundation `ArtifactReference` identities separated from explicit `ArtifactAvailability` bindings.
- Local artifact reads are bounded, integrity-verified, root-capability scoped, and report close failure.
- Exact release content, approval, qualification, database revision, dependency graph, and active retention inventories are validated without subset fallback.
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
