import Foundation

public enum FoundryHandoffManifestError: Error, Sendable, Equatable, LocalizedError {
    case nonCanonicalEncoding

    public var errorDescription: String? {
        switch self {
        case .nonCanonicalEncoding:
            return "Foundry handoff manifest is not canonically encoded."
        }
    }
}
