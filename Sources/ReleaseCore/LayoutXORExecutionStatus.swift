public enum LayoutXORExecutionStatus: String, Sendable, Hashable, Codable {
    case notExecuted = "not-executed"
    case completed
    case exitedWithFailure = "exited-with-failure"
    case launchFailed = "launch-failed"
    case timedOut = "timed-out"
    case cancelled
    case invalidReport = "invalid-report"
    case artifactPersistenceFailed = "artifact-persistence-failed"
    case unqualified
}
