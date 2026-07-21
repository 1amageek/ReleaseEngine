# ReleaseEngine Milestones

ReleaseEngine owns technical signoff evaluation, tapeout packaging, and final release authorization. It does not qualify tools, approve its own output, or own flow persistence.

## M0 — Responsibility boundary and canonical artifacts

Status: complete.

- Requests and results are typed domain values.
- Artifact identity, integrity, diagnostics, and provenance use CircuiteFoundation.
- ReleaseEngine does not import Xcircuite or UI code.
- Tool trust decisions are owned by ToolQualification.
- Run lifecycle and human approval records are owned by DesignFlowKernel.

## M1 — Native signoff evaluation

Status: complete.

- Digital, analog, and mixed-signal profiles define exact release-axis coverage.
- Required, failed, blocked, profile-approved-not-applicable, and waived states are explicit.
- Evidence integrity, design/PDK/tool binding, freshness, and waiver scope fail closed.
- The evaluator generates the canonical bundle, persists it immutably, reloads exact bytes, and retains operational evidence artifacts plus production qualification scopes.
- `release-engine signoff` emits a typed `SignoffResult`; it never grants human approval.

## M2 — Tapeout packaging and foundry handoff

Status: complete.

- The tapeout path generates the stream-out and foundry handoff, persists both immutably, and requires a zero-difference report from an externally qualified geometric XOR executable. Byte identity remains diagnostic-only.
- Canonical bytes, digests, byte counts, design identity, PDK identity, and top-cell identity are checked before completion.
- `release-engine tapeout` emits a typed `TapeoutResult`; completion means packaging is internally consistent, not that release is authorized.

## M3 — Independent tool trust input

Status: complete.

- Release authorization derives required producer scopes from the canonical bundle and accepts exactly matching production ToolQualification request/decision pairs.
- The authorizer recomputes each decision through an injected ToolQualification engine and compares it with the supplied decision.
- Scope, capability, implementation identity, retained evidence, freshness, and evaluation time must match exactly.
- ReleaseEngine contains no tool-qualification gate, promotion model, or self-issued trust state.

## M4 — Human-bound release authorization

Status: complete.

- `ReleaseAuthorizationRequest` binds a human `FlowApprovalRecord` to the exact run, release stage, and canonical signoff bundle artifact.
- Authorization requires exact unique coverage of every release axis, including logic, RTL verification, DFT, and power intent, and independently reproducible eligible trust for every required tool.
- Rejected, non-human, stale, mismatched, incomplete, duplicated, or self-referential input remains blocked with typed diagnostics.
- `release-engine authorize` emits `.authorized` only when every technical, trust, integrity, and approval condition passes.

## M5 — Xcircuite and DesignFlowKernel composition

Status: complete at the package boundary.

- Xcircuite owns concrete workspace persistence and invokes ReleaseEngine protocols directly.
- DesignFlowKernel owns run transitions, approval capture, review, and resume.
- ToolQualification owns capability and trust decisions.
- ReleaseEngine remains independently buildable and has no storage adapter or compatibility facade.

## External release evidence

Package completion does not manufacture foundry acceptance. A real release remains blocked until callers supply the selected process profile, foundry decks, qualified external tool evidence, exact artifacts, and an authorized human decision. This is an evidence condition, not an unimplemented ReleaseEngine API.
