# Release Qualification Boundary

ReleaseEngine does not qualify tools. ToolQualification validates raw corpus, oracle, health, identity, scope, freshness, and artifact integrity. Release authorization receives the ToolQualification inputs and decision, re-runs that evaluation against retained artifacts, and requires exact equality with the supplied decision.

Human approval is a separate DesignFlowKernel record bound to the final signoff bundle. Neither a tool trust decision nor a technical signoff result can substitute for that approval. Foundry acceptance remains external evidence and cannot be inferred by this package.
