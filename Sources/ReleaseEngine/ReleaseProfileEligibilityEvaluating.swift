import Foundation

public protocol ReleaseProfileEligibilityEvaluating: Sendable {
    func execute(
        _ request: ReleaseProfileEligibilityRequest
    ) async throws -> ReleaseProfileEligibilityResult
}
