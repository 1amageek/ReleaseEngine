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

The package does not claim that a native implementation is qualified for a foundry process. A release is eligible only when the request carries the required process-scoped tool qualification evidence. `QualificationEngine` validates retained corpus suite/report artifacts, freshness, integrity, lane coverage, thresholds, `ToolQualificationScope`, and case-level native/oracle correlation with fail-closed typed diagnostics. It emits explicit `corpusChecked`, `oracleChecked`, and `productionEligible` promotion states; production promotion requires qualified production-approval evidence. External-tool invocation, corpus retention publication, process approval, human approval, and resume policy remain owned by the Xcircuite/ToolQualification/DesignFlowKernel integration layer. Xcircuite provides release signoff, tapeout, and qualification stage adapters that load project-relative requests, inject the flow project root, persist raw envelopes, and map typed status and gates.

The exact-stream comparator is deliberately not a geometric XOR oracle. A different byte encoding is not treated as equivalent without a qualified geometry comparator.

## Structured oracle contract

An external lane must identify its backend, corpus specification artifact, report artifact, and required probes. The retained suite declares the case IDs, domains, coverage tags, and probes. The native and oracle reports must return the same case set and explicitly state per-case agreement. Aggregate pass rates cannot substitute for case-level agreement.

The evaluator blocks or fails with typed diagnostics for unavailable oracle output, case-set drift, coverage/probe drift, status mismatch, and explicit disagreement. This makes the contract suitable for an external backend while keeping ReleaseEngine deterministic and local.

## Promotion contract

Promotion is evaluated per request and scope. A fresh, scope-matching oracle lane can promote a process to `oracleChecked`. `productionEligible` additionally requires fresh qualified `productionApproval` evidence. The resulting promotion status and failure codes are persisted in `ReleaseQualificationPayload`; no foundry or human decision is inferred from a native pass.

## Reproduction

Run the package tests with a timeout and invoke the JSON CLI against a request artifact:

```bash
perl -e 'alarm shift; exec @ARGV' 60 swift test
swift run release-engine profile --profile mixed-signal
swift run release-engine qualify --request qualification-request.json
```

The test suites create project-relative artifacts, record their digests and exercise approval, stale-evidence, missing-oracle, weak-metric, scope, and tamper fail-closed paths.
