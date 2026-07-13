import Foundation
import CircuiteFoundation
import ReleaseCore

public protocol SignoffEvaluating: Sendable {
    func execute(
        _ request: SignoffRequest
    ) async throws -> SignoffResult
}
