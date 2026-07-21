import CircuiteFoundation
import ReleaseCore

public protocol ReleaseAuthorizing: Engine
where Request == ReleaseAuthorizationRequest, Output == ReleaseAuthorizationResult {}
