import Foundation

public enum FoundationReleaseProfileEligibilityError: Error, Sendable, Equatable, LocalizedError {
    case invalidDiagnosticCode(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDiagnosticCode(let code):
            "Release profile produced an invalid diagnostic code: \(code)"
        }
    }
}
