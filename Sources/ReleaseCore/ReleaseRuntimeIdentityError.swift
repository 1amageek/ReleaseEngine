import Foundation

public enum ReleaseRuntimeIdentityError: Error, Sendable, Hashable, LocalizedError {
    case executableAttestationFailed

    public var errorDescription: String? {
        "The executable carrying the release implementation could not be attested."
    }
}
