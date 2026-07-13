import Foundation
import ReleaseCore
import CircuiteFoundation

public struct StreamOutValidationResult: Sendable, Hashable, Codable {
    public var status: LayoutXORStatus
    public var diagnostics: [DesignDiagnostic]

    public init(
        status: LayoutXORStatus,
        diagnostics: [DesignDiagnostic] = []
    ) {
        self.status = status
        self.diagnostics = diagnostics
    }
}
