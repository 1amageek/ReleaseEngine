import Foundation

public enum SignoffBundleCanonicalEncodingError: Error, LocalizedError, Sendable {
    case decodedBundleIsNotCanonical

    public var errorDescription: String? {
        switch self {
        case .decodedBundleIsNotCanonical:
            "The stored signoff bundle does not use the canonical encoding."
        }
    }
}
