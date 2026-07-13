# Release-profile eligibility fixture

`blocked/request.json` is a deterministic negative fixture for the
`release-engine eligibility` command. It remains blocked because the requested
promotion level is `productionEligible`, the supplied qualification is only
`corpusChecked`, and the approval is from an agent rather than a human and is
not bound to the decision-packet digest.

Run it after building from the repository root:

    swift run release-engine eligibility --request Fixtures/Eligibility/blocked/request.json

The command is expected to exit with code 2 and emit structured diagnostic
codes.
