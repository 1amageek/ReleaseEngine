import Foundation

public enum GeometricXORToolConfigurationError: Error, Sendable, Equatable, LocalizedError {
    case invalidTimeout(Double)
    case invalidReportArtifact
    case argumentContainsControlCharacter(String)
    case reservedArgument(String)
    case environmentContainsControlCharacter(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTimeout(let timeout):
            return "Geometric XOR timeout must be positive and finite: \(timeout)."
        case .invalidReportArtifact:
            return "Geometric XOR report output must be a workspace-relative JSON report artifact."
        case .argumentContainsControlCharacter(let argument):
            return "Geometric XOR argument contains a control character: \(argument)."
        case .reservedArgument(let argument):
            return "Geometric XOR argument is owned by the executor: \(argument)."
        case .environmentContainsControlCharacter(let key):
            return "Geometric XOR environment entry contains a control character: \(key)."
        }
    }
}
