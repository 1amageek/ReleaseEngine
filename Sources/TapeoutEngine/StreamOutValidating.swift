import Foundation
import ReleaseCore

public protocol StreamOutValidating: Sendable {
    func validate(
        _ request: StreamOutRequest
    ) async -> StreamOutValidationResult
}
