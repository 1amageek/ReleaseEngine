import Foundation
import CircuiteFoundation

public protocol ReleaseQualificationEvaluating: Sendable {
    func execute(
        _ request: ReleaseQualificationRequest
    ) async throws -> ReleaseQualificationResult
}
