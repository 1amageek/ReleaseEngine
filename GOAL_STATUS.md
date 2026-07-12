# ReleaseEngine Goal Status

## Current state

**Native contract path and retained-corpus qualification input are implemented. External oracle correlation, process promotion, human approval, and release-envelope eligibility remain explicit integration milestones.**

| Maturity gate | Status | Evidence |
|---|---|---|
| Responsibility boundary | Complete | README.md and DESIGN.md |
| Public package products | Implemented | Package.swift (`ReleaseCore`, `SignoffEngine`, `TapeoutEngine`, `QualificationEngine`) |
| Shared Xcircuite request/result contract | Implemented | Public Swift requests, payloads, protocols and result envelopes |
| Contract build | Passed | timeout-bounded `swift build` |
| Contract test | Passed | timeout-bounded `swift test` suites; the package has no configured Xcode test action |
| Domain implementation | Complete for native contract path | DefaultSignoffEvaluator and DefaultTapeoutPackaging |
| CLI implementation | Complete for native and retained qualification paths | `release-engine profile/signoff/tapeout/qualify` |
| Fixture corpus | Retained qualification regression corpus | ReleaseEngineBehaviorTests, RetainedQualificationTests and Fixtures |
| Oracle correlation | Not claimed | Requires external/reference geometry oracle |
| Process qualification | Not claimed | Requires PDK-scoped retained qualification evidence |
| Xcircuite stage adapter | Implemented for signoff, tapeout and qualification | Release stage executors and persisted raw envelopes |
| End-to-end flow evidence | Native + qualification input path complete | ReleaseEngine qualification suite and Xcircuite release adapter suite |
| Release readiness | Blocked by qualification policy | No process/foundry approval is inferred |

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
- No external oracle correlation or production process qualification is claimed.
- Xcircuite remains responsible for flow approval and resume policy; release stage adapters persist raw envelopes and map typed status/gates.

This file must be updated by implementation agents whenever a maturity gate changes. A source file or type name alone is never evidence of implementation or qualification.
