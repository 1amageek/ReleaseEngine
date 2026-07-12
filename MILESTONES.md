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

Status: complete for the structured oracle-correlation contract.

Contract requirements:

- Each required oracle lane identifies its backend, corpus, probe and report artifact.
- Native and external lane case IDs/coverage tags are comparable.
- Agreement, mismatch and oracle-unavailable states are retained per domain.
- No oracle agreement is inferred from native pass rate.

Exit evidence:

- Required external lanes identify backend, corpus specification, report and probes.
- Native and oracle case IDs, domains, coverage tags, probe IDs, statuses and explicit agreement are correlated one-to-one.
- Case-set mismatch, coverage mismatch, probe mismatch, unavailable oracle and disagreement produce typed fail-closed diagnostics.
- `RetainedQualificationTests` covers passing correlation, case disagreement and case-set mismatch.

M3 boundary:

- ReleaseEngine consumes structured oracle evidence; it does not invoke an external geometry or signoff binary.
- Backend execution and oracle artifact production remain owned by the Xcircuite/tool integration layer.

## M4 — Process-scoped qualification and promotion

Status: complete for the process-scoped promotion contract.

Contract requirements:

- `ToolQualificationScope` matches implementation, binary, algorithm, process and deck digests.
- Promotion to `oracleChecked` or `productionEligible` requires the corresponding retained evidence kinds and freshness.
- Scope mismatch, stale evidence and future timestamps block promotion.

Exit evidence:

- Fresh, scope-matching failed evidence is reported as a failed qualification lane; missing or unscoped evidence remains blocked.
- Production promotion requires an explicit qualified production-approval evidence item.
- Promotion status and failure codes are persisted in `ReleaseQualificationPayload`.
- `RetainedQualificationTests` covers oracle-checked and production-eligible promotion paths.

M4 boundary:

- Process promotion is a deterministic evaluation of supplied evidence. It is not foundry approval and does not manufacture production evidence.

## M5 — Retention CI and release envelope

Status: partially complete.

Exit evidence:

- Workflow run, history, dashboard and retention-index artifacts are immutable and cross-referenced.
- Missing, short-retention, stale or non-append-only history blocks the release envelope.
- DesignFlowKernel owns the envelope builder; ReleaseEngine supplies typed qualification evidence.

Current evidence:

- DesignFlowKernel validates a hash-chained JSONL qualification history, source dashboard digest, append-only advancement and minimum retention window.
- `design-flow build-retention-index` persists `qualification/retention-index.json` and registers `qualification-retention-index` in the run manifest.
- `design-flow validate-retention-index` exposes the same validation contract to Agent and CI callers.
- Release envelopes consume and content-validate both the raw ReleaseEngine qualification result and the retention index.

Remaining exit evidence:

- A repository-owned CI workflow must execute the retention build/validation commands against the retained corpus and publish the resulting run artifacts.
- CI artifact upload and retention policy configuration must be verified in the target hosting environment.

## M6 — Xcircuite headless flow and human approval/resume

Status: complete for the qualification-stage approval/resume path.

Current evidence:

- Release signoff and tapeout stage adapters load project-relative requests, persist raw envelopes and map typed status/gates.
- The qualification stage adapter loads a project-relative qualification request, injects the flow project root, persists the raw envelope, and maps `payload.qualified` to the release gate.
- The qualification adapter participates in the shared run ledger approval gate; an approved `release.qualification` stage resumes with the same run ID and registered result artifact.

Remaining hardening evidence:

- Multi-stage signoff → qualification → tapeout lineage and explicit waiver/rejection policy still need a release-profile integration fixture.
- The shared kernel approval/resume contract is covered; the complete profile-level release packet remains an M7 concern.

## M7 — Release-profile eligibility

Status: blocked.

Exit evidence:

- M0–M6 exit evidence is present for the selected process profile.
- A human approval record references the final signoff bundle, qualification digest and handoff manifest.
- A reproducible release decision packet can be inspected by both Agent and human.

Current blockers are tracked in `GOAL_STATUS.md` and `QUALIFICATION.md`. A source type, local smoke test or successful build never closes a qualification milestone by itself.
