import Foundation
import ReleaseCore
import XcircuitePackage

public struct StreamOutValidationResult: Sendable, Hashable, Codable {
    public var status: LayoutXORStatus
    public var diagnostics: [XcircuiteEngineDiagnostic]

    public init(
        status: LayoutXORStatus,
        diagnostics: [XcircuiteEngineDiagnostic] = []
    ) {
        self.status = status
        self.diagnostics = diagnostics
    }
}
