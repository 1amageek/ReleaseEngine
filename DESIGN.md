# ReleaseEngine Design

## Purpose

Fail-closed multi-axis signoff and immutable tapeout release contracts.

## Responsibility boundary

This package owns the schemas and engine protocols listed in its public products. It must remain usable without UI state and without the Xcircuite runtime.

## Non-responsibilities

- Executing domain analyses
- Repairing design data
- Converting blocked evidence into a pass

## Dependency direction

```text
standard artifacts / canonical references
                 ↓
ReleaseEngine protocols and result schemas
                 ↓
native or external-tool backends
                 ↓
Xcircuite stage adapters
                 ↓
DesignFlowKernel and .xcircuite artifacts
```

Backends may depend on lower-level data packages. This package must never import `Xcircuite` or `circuit-studio`.

## Trust model

Kernel availability, corpus validation, oracle correlation, process-scoped qualification and release approval are distinct states. The package reports capability and evidence; Xcircuite and ToolQualification apply flow policy.

## Artifact requirements

All outputs are immutable run artifacts with format, digest, producer metadata and the input design/PDK revision needed to reproduce the result.
