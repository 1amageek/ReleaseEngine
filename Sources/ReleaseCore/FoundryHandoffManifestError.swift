import Foundation

public enum FoundryHandoffManifestError: Error, Sendable, Equatable, LocalizedError {
    case nonCanonicalEncoding
    case unsupportedSchemaVersion(Int)
    case invalidContent

    public var errorDescription: String? {
        switch self {
        case .nonCanonicalEncoding:
            return "Foundry handoff manifest is not canonically encoded."
        case .unsupportedSchemaVersion(let version):
            return "Foundry handoff manifest schema version \(version) is not supported."
        case .invalidContent:
            return "Foundry handoff manifest content is incomplete, duplicated, or not self-consistent."
        }
    }
}
