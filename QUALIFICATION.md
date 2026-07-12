# ReleaseEngine Capability and Qualification Boundary

## Native capability

The package implements deterministic, protocol-first release decisions for:

| Capability | Native behavior | Decision on missing semantics |
|---|---|---|
| Signoff profile | Digital, analog, and mixed-signal required-axis profiles | Blocked |
| Evidence integrity | Project-relative path, SHA-256, byte count, design/PDK/tool binding | Blocked |
| Tool qualification | Minimum `ToolQualificationLevel` per axis | Blocked |
| Waiver governance | Authority, rationale, expiry, evidence scope, revision scope | Blocked |
| Signoff bundle | Immutable approval fingerprint bound to final layout | Blocked |
| Stream-out | GDSII/OASIS signature and manifest checks | Failed or blocked |
| XOR | Exact byte-stream identity | Failed when bytes differ |
| Foundry handoff | Deterministic artifact/evidence manifest and checksum | Blocked |

## Qualification boundary

The package does not claim that a native implementation is qualified for a foundry process. A release is eligible only when the request carries the required process-scoped tool qualification evidence. `QualificationEngine` now validates retained corpus suite/report artifacts, freshness, integrity, lane coverage, thresholds, and `ToolQualificationScope` with fail-closed typed diagnostics. External-tool invocation, corpus retention policy, oracle correlation, process approval, human approval, and resume policy remain owned by the Xcircuite/ToolQualification integration layer. Xcircuite provides release signoff, tapeout, and qualification stage adapters that load project-relative requests, inject the flow project root, persist raw envelopes, and map typed status and gates.

The exact-stream comparator is deliberately not a geometric XOR oracle. A different byte encoding is not treated as equivalent without a qualified geometry comparator.

## Reproduction

Run the package tests with a timeout and invoke the JSON CLI against a request artifact:

```bash
perl -e 'alarm shift; exec @ARGV' 60 swift test
swift run release-engine profile --profile mixed-signal
swift run release-engine qualify --request qualification-request.json
```

The test suites create project-relative artifacts, record their digests and exercise approval, stale-evidence, missing-oracle, weak-metric, scope, and tamper fail-closed paths.
