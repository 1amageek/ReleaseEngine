# ReleaseEngine Milestones

ReleaseEngine has two different completion dimensions:

1. Native contract capability: the package can evaluate structured requests deterministically.
2. Release readiness: a process-scoped, retained, oracle-correlated, human-approved release can be reproduced and resumed.

Native capability is not evidence of process qualification. Every milestone below has an exit evidence contract and a fail-closed condition.

## M0 — Responsibility boundary and canonical artifacts

Status: complete.

Exit evidence:

- ReleaseEngine owns typed release contracts and native validators.
- Standard artifacts and `XcircuiteFileReference` remain the source of truth.
- ReleaseEngine does not import Xcircuite or UI code.

## M1 — Native signoff and tapeout decision path

Status: complete.

Exit evidence:

- Digital, analog, and mixed-signal profiles exist.
- Required, failed, blocked, profile-approved-not-applicable, and waived states are explicit.
- Artifact integrity, design/PDK/tool binding, stream-out validation, exact-stream comparison, immutable bundle and handoff checks pass regression tests.
- Deterministic `release-engine profile/signoff/tapeout` commands exist.

## M2 — Retained corpus qualification input

Status: complete for retained-corpus qualification input.

Scope:

- Parse retained corpus suite and report artifacts without depending on DesignFlowKernel.
- Verify suite/report/evidence artifact integrity and report provenance.
- Enforce domain/lane coverage, case count, coverage, pass rate, freshness, process scope and qualification thresholds.
- Emit a typed qualification result that is consumable by SignoffEngine and Xcircuite.

Exit evidence:

- Positive retained corpus fixture produces `completed` + `qualified=true`.
- Missing oracle lane, stale report, tampered artifact, missing process scope and weak metrics produce structured fail-closed results.
- JSON round-trip and seven retained-qualification regression tests pass.
- `release-engine qualify --request <path|->` and the Xcircuite `release.qualification` adapter are implemented; the adapter persists the result envelope under the run stage.

M2 boundary:

- This milestone validates retained evidence input and native corpus policy evaluation.
- It does not claim that an external oracle result exists, that the process is production-qualified, or that a human has approved the release.

## M3 — Reference oracle correlation

Status: pending.

Exit evidence:

- Each required oracle lane identifies its backend, corpus, probe and report artifact.
- Native and external lane case IDs/coverage tags are comparable.
- Agreement, mismatch and oracle-unavailable states are retained per domain.
- No oracle agreement is inferred from native pass rate.

## M4 — Process-scoped qualification and promotion

Status: pending.

Exit evidence:

- `ToolQualificationScope` matches implementation, binary, algorithm, process and deck digests.
- Promotion to `oracleChecked` or `productionEligible` requires the corresponding retained evidence kinds and freshness.
- Scope mismatch, stale evidence and future timestamps block promotion.

## M5 — Retention CI and release envelope

Status: pending.

Exit evidence:

- Workflow run, history, dashboard and retention-index artifacts are immutable and cross-referenced.
- Missing, short-retention, stale or non-append-only history blocks the release envelope.
- DesignFlowKernel owns the envelope builder; ReleaseEngine supplies typed qualification evidence.

## M6 — Xcircuite headless flow and human approval/resume

Status: partially complete.

Current evidence:

- Release signoff and tapeout stage adapters load project-relative requests, persist raw envelopes and map typed status/gates.
- The qualification stage adapter loads a project-relative qualification request, injects the flow project root, persists the raw envelope, and maps `payload.qualified` to the release gate.

Remaining exit evidence:

- Qualification stage adapter is persisted in the same run ledger.
- Approval, waiver, rejection and resume actions preserve the same bundle, scope and artifact lineage.
- A headless run can stop at a blocked/approval gate and resume without rebuilding unrelated evidence.

## M7 — Release-profile eligibility

Status: blocked.

Exit evidence:

- M0–M6 exit evidence is present for the selected process profile.
- A human approval record references the final signoff bundle, qualification digest and handoff manifest.
- A reproducible release decision packet can be inspected by both Agent and human.

Current blockers are tracked in `GOAL_STATUS.md` and `QUALIFICATION.md`. A source type, local smoke test or successful build never closes a qualification milestone by itself.
