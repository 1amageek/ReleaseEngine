import CircuiteFoundation

/// Foundation engine seam for release-profile eligibility.
public protocol FoundationReleaseProfileEligibilityEngine: Engine
where Request == FoundationReleaseProfileEligibilityRequest,
      Output == FoundationReleaseProfileEligibilityResult
{}
