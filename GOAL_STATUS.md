# ReleaseEngine Goal Status

## Current state

**Native contract path, structured oracle correlation, process-scoped promotion, retention CI, release-profile eligibility, and multi-stage approval/resume are implemented. Final process/foundry evidence remains an explicit fail-closed release gate.**

| Maturity gate | Status | Evidence |
|---|---|---|
| Responsibility boundary | Complete | README.md and DESIGN.md |
| Public package products | Implemented | Package.swift (`ReleaseCore`, `SignoffEngine`, `TapeoutEngine`, `QualificationEngine`) |
| Shared Xcircuite request/result contract | Implemented | Public Swift requests, payloads, protocols and result envelopes |
| Contract build | Passed | timeout-bounded `swift build` |
| Contract test | Passed | timeout-bounded `swift test` suites; the package has no configured Xcode test action |
| Domain implementation | Complete for native contract path | DefaultSignoffEvaluator and DefaultTapeoutPackaging |
| CLI implementation | Complete for native, retained qualification and release-profile eligibility paths | `release-engine profile/signoff/tapeout/qualify/eligibility` |
| Fixture corpus | Retained qualification regression corpus | ReleaseEngineBehaviorTests, RetainedQualificationTests and Fixtures |
| Oracle correlation | Implemented for structured evidence | ReleaseEngine correlates supplied native/oracle case results; backend execution remains external |
| Process qualification | Promotion contract implemented | Requires fresh PDK-scoped evidence and explicit production approval |
| Xcircuite stage adapter | Implemented for signoff, qualification, tapeout and release-profile eligibility | Release stage executors, runtime specs, descriptors and persisted raw envelopes |
| End-to-end flow evidence | Native + structured oracle + multi-stage approval/resume path complete | ReleaseEngine eligibility suite, DesignFlowKernel retention/envelope suite, Xcircuite release lineage suite |
| Release readiness | Evidence-gated | Process/foundry approval is never inferred |

## Function status

| Function | Contract | Implementation | Validation corpus | Qualification |
|---|---|---|---|---|
| Signoff profile | Implemented | DefaultSignoffProfileProvider | Positive/negative tests | Qualification input required |
| Applicability resolution | Implemented | DefaultSignoffEvaluator | Profile assertions | Qualification input required |
| Evidence validation | Implemented | DefaultSignoffEvidenceValidator | Integrity and mismatch tests | Qualification input required |
| Waiver governance | Implemented | Scoped waiver validator | Expired waiver regression | Authority remains external |
| Signoff bundle | Implemented | Immutable bundle fingerprint | Approval and binding tests | Human approval remains external |
| Stream-out validation | Implemented | DefaultStreamOutValidator | GDSII metadata/signature tests | PDK deck qualification remains external |
| XOR and release checks | Implemented | DefaultLayoutXORComparator | Exact-stream pass/block tests | Geometry oracle not bundled |
| Foundry handoff | Implemented | DefaultTapeoutPackaging | Deterministic manifest test | Foundry acceptance remains external |

## Goal progression

```text
contract scaffold
      ↓
narrow implementation
      ↓
negative-path fixtures
      ↓
corpus validation
      ↓
reference-oracle correlation
      ↓
process-scoped qualification
      ↓
Xcircuite integration and repair loop
      ↓
release-profile eligibility
```

## Completion definition

The package goal is complete only when every P0 function has a concrete backend, structured failure behavior, retained corpus, reference correlation where an oracle exists, process-scoped qualification where required, a deterministic CLI and a passing Xcircuite headless integration test.

## Current blockers

- No external-tool invocation is bundled; native engines consume structured evidence.
- External oracle execution and production process qualification are not manufactured by this package.
- Final process/foundry evidence remains external by design; a missing or stale approval keeps release-profile eligibility blocked.
- `release-profile` is now a native and headless integration contract; it returns blocked until the supplied process-scoped evidence and human approval satisfy policy.
- Xcircuite remains responsible for external backend execution and flow orchestration; release stage adapters persist raw envelopes and map typed status/gates.

This file must be updated by implementation agents whenever a maturity gate changes. A source file or type name alone is never evidence of implementation or qualification.
