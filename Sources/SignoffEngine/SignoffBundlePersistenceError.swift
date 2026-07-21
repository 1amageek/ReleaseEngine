import Foundation

public enum SignoffBundlePersistenceError: Error, Sendable, Hashable, LocalizedError {
    case referenceMismatch
    case contentMismatch

    public var errorDescription: String? {
        switch self {
        case .referenceMismatch:
            "The persisted signoff bundle reference does not match the requested locator, producer, digest, or byte count."
        case .contentMismatch:
            "The reloaded signoff bundle bytes do not match the generated canonical bundle."
        }
    }
}
