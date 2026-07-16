import CircuiteFoundation

public protocol ReleaseAuthorizing: Engine
where Request == ReleaseAuthorizationRequest, Output == ReleaseAuthorizationResult {}
