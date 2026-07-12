# ReleaseEngine Implementation Plan

## Order

1. Signoff profile and axis states
2. Evidence digest and qualification binding
3. Waiver and approval records
4. Stream-out and XOR contracts
5. Foundry release manifest

## First implementation slice

- Implement one narrow, explicitly declared capability.
- Add a deterministic fixture and negative-path fixture.
- Add JSON request/result round-trip tests.
- Add a CLI surface after the typed API is stable.
- Add a retained corpus before raising qualification above smoke-checked.

## Native implementation status

The native implementation slice and retained-corpus qualification input are complete. `ReleaseCore` contains the release value contracts, `SignoffEngine` provides profile lookup, evidence validation, waiver validation, and a fail-closed evaluator, `TapeoutEngine` provides stream-out validation, exact-stream comparison, binding checks, and deterministic handoff manifests, and `QualificationEngine` evaluates retained suite/report artifacts with process-scoped policy gates. The `release-engine` executable exposes deterministic JSON profile, signoff, tapeout, and qualify commands.

External oracle correlation, production process promotion, and human approval remain explicit milestones. Retained qualification input is implemented here; Xcircuite owns the flow adapter and run-stage artifact persistence rather than a native package-local release envelope.

## Completion gates

- Public APIs remain protocol-first and Sendable.
- Every unsupported semantic produces a structured blocked result.
- Native and external backends produce the same result schema.
- No UI type enters a public contract.
- No result claims foundry qualification without process-scoped oracle evidence.
- Xcircuite can execute, persist, review and resume the stage without circuit-studio.
