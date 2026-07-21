import Foundation

public enum SignoffBundleCanonicalEncodingError: Error, LocalizedError, Sendable {
    case decodedBundleIsNotCanonical
    case unsupportedSchemaVersion(Int)
    case invalidReleaseContent

    public var errorDescription: String? {
        switch self {
        case .decodedBundleIsNotCanonical:
            "The stored signoff bundle does not use the canonical encoding."
        case .unsupportedSchemaVersion(let version):
            "The stored signoff bundle schema version \(version) is not supported."
        case .invalidReleaseContent:
            "The stored signoff bundle does not contain complete, unique, production-qualified release content."
        }
    }
}
