import Foundation
import CircuiteFoundation
import ReleaseCore
import PhysicalDesignCore
import PDKCore

public protocol TapeoutPackaging: Sendable {
    func execute(
        _ request: TapeoutRequest
    ) async throws -> TapeoutResult
}
