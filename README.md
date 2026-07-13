# ReleaseEngine

Fail-closed multi-axis signoff and immutable tapeout release contracts.

## Status

This repository provides native, fail-closed release contract engines. It does not invoke a foundry tool or infer process qualification; qualification evidence is an explicit input and missing or stale semantics remain blocked.

The current implementation closes the native release-contract path, structured native/oracle case correlation, process-scoped promotion evaluation, and release-profile eligibility evaluation. DesignFlowKernel owns approval and resume while Xcircuite supplies concrete persistence. A release is still blocked unless CI retention evidence and final process/foundry approval are supplied; the remaining evidence criteria are tracked in [`MILESTONES.md`](MILESTONES.md).

The canonical release-profile eligibility path implements the
`CircuiteFoundation.Engine` contract. It consumes `ArtifactReference` values,
produces structured `DesignDiagnostic` values, and records an
`ExecutionProvenance`/`EvidenceManifest` that binds the reviewed artifacts and
human approval to the decision.

## Products

| Product | Responsibility |
|---|---|
| `ReleaseCore` | Signoff and tapeout references |
| `SignoffEngine` | Required-axis applicability and verdict |
| `TapeoutEngine` | Stream-out validation, exact-stream XOR and foundry handoff |
| `QualificationEngine` | Retained corpus lane evaluation, case-level oracle correlation, and process-scoped promotion |
| `ReleaseEngine` | Umbrella API and release-profile eligibility evaluator |

## Implemented behavior

- Built-in digital, analog, and mixed-signal signoff profiles.
- Required, failed, blocked, and profile-approved-not-applicable axis states.
- SHA-256/byte-count verification, design/PDK/tool provenance binding, qualification thresholds, and cross-axis revision checks.
- Scoped, authority-bound, time-limited waivers that retain the original failed evidence.
- Immutable signoff bundle fingerprints bound to a final layout digest.
- GDSII/OASIS stream-out manifest validation, top-cell/units/layer/hierarchy/seal/pad checks, exact-stream comparison, and deterministic foundry handoff manifest checksums.
- Deterministic JSON CLI with non-zero exit codes for blocked and failed decisions.
- Retained-corpus qualification evaluation with artifact integrity, freshness, coverage, metric, oracle-lane and process-scope gates.
- Case-level native/oracle correlation with explicit agreement, backend/corpus/probe binding, and fail-closed mismatch diagnostics.
- Explicit promotion status (`corpusChecked`, `oracleChecked`, `productionEligible`) with production-approval evidence gating.
- Release-profile eligibility that correlates signoff, qualification and tapeout stage artifacts under one run ID, checks design/PDK binding, requires the configured qualification/promotion level and exact process qualification scope, and binds a human approval to the final decision-packet digest.

The exact-stream comparator intentionally does not claim geometric XOR equivalence when a qualified geometry backend is unavailable. Such a case remains failed or blocked according to the release requirement.

## Contract

The Foundation release-profile API uses:

- a `Sendable`, `Hashable`, `Codable` request containing canonical artifact references;
- `FoundationReleaseProfileEligibilityEngine`, which refines `Engine<Request, Output>`;
- a result conforming to `ArtifactProducing`, `DiagnosticReporting`, and `EvidenceProviding`;
- typed `ContentDigest` and `ExecutionProvenance` values for release evidence;
- explicit blocked and eligible states, with human approval bound to the decision-packet digest.

All stage APIs use domain-specific `Codable`, `Hashable`, `Sendable` requests
and results. Cross-engine artifacts are immutable `ArtifactReference` values,
diagnostics are `DesignDiagnostic`, and execution evidence is
`ExecutionProvenance`; no compatibility envelope or adapter layer is required.

## Xcircuite integration

Xcircuite gathers all stage evidence and invokes QualificationEngine, SignoffEngine, and TapeoutEngine through their public protocols. TapeoutEngine accepts only the resulting approved bundle bound to the same layout, PDK, tool and waiver digests.

The library does not depend on the Xcircuite runtime. Xcircuite owns concrete artifact persistence and composition with `DesignFlowKernel.FlowStageExecutor`; the engine remains directly protocol-conformant and independently usable.

## Build

```bash
swift build
```

The CLI is available as:

```bash
swift run release-engine profile --profile digital
swift run release-engine signoff --request request.json
swift run release-engine tapeout --request request.json
swift run release-engine qualify --request qualification-request.json
swift run release-engine eligibility --request release-profile-request.json
```

`eligibility` emits a completed envelope only when signoff, qualification and tapeout are completed and approved, the qualification/promotion thresholds and exact process qualification scope are met, all process and design digests agree, and a human approval references the final decision packet. Missing or mismatched scope/production evidence is a structured blocked result.

## Test

```bash
perl -e 'alarm shift; exec @ARGV' 120 swift test
```

The checked-in positive qualification fixture can be replayed through the CLI after building:

```bash
swift build
cd Fixtures/Qualification/positive
../../../.build/debug/release-engine qualify --request request.json
```

The command exits successfully only when the request, retained corpus, report, artifact references, freshness windows, process scope and oracle agreement satisfy the fail-closed policy.

For the complete flow, DesignFlowKernel persists the qualification result under
`.xcircuite/runs/<run-id>/stages/release.qualification/raw/result.json`, builds a
hash-chained retention index, and consumes both artifacts when it builds the
release envelope. The developer/Agent-facing retention commands are:

```bash
design-flow build-retention-index --project-root <path> --run-id <id> --workflow-run-id <id> --source-dashboard <path> --history <path> --previous-entry-count <n> --retention-days <n> --minimum-retention-days <n>
design-flow validate-retention-index --project-root <path> --run-id <id>
design-flow build-release-envelope --project-root <path> --run-id <id>
```

See `DESIGN.md`, `INTERFACES.md` and `IMPLEMENTATION_PLAN.md` for the responsibility boundary and extension points.

See `QUALIFICATION.md` for the capability boundary and retained-evidence policy.

## Continuous integration

`.github/workflows/release-engine.yml` builds the local package graph, runs the complete test target, replays the checked-in retained qualification fixture, and uploads the resulting JSON evidence with a 90-day artifact retention policy. DesignFlowKernel owns the hash-chained retention index and release envelope; its published retention workflow executes both CLI commands and uploads the run artifacts. A successful workflow proves reproducibility, not foundry approval.
