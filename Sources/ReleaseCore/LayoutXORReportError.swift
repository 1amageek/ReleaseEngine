import Foundation

public enum LayoutXORReportError: Error, Sendable, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case invalidDifferenceArea(Double)
    case nonCanonicalEncoding

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported layout XOR report schema version: \(version)."
        case .invalidDifferenceArea(let area):
            return "Layout XOR difference area must be finite and non-negative: \(area)."
        case .nonCanonicalEncoding:
            return "Layout XOR report is not canonically encoded."
        }
    }
}
