import Foundation

public enum LocalReleaseArtifactStoreError: Error, Sendable, Hashable, LocalizedError {
    public enum Stage: String, Sendable, Hashable {
        case directoryCreation
        case contentWrite
        case permissionUpdate
        case fileSynchronization
        case publication
        case directorySynchronization
    }

    case targetAlreadyExists(String)
    case invalidLocation(String)
    case writeFailed(path: String, stage: Stage)
    case cleanupFailed(path: String, originalStage: Stage)
    case readFailed(String)
    case readBudgetExceeded(String)
    case readIntegrityFailed(String)
    case readCancelled(String)
    case readCleanupFailed(
        path: String,
        primaryReason: String?,
        closeReason: String
    )

    public var errorDescription: String? {
        switch self {
        case .targetAlreadyExists(let path):
            "The immutable release artifact already exists at \(path)."
        case .invalidLocation(let path):
            "The release artifact location must be project-relative: \(path)."
        case .writeFailed(let path, let stage):
            "The release artifact could not be written at \(path) during \(stage.rawValue)."
        case .cleanupFailed(let path, let originalStage):
            "Release artifact cleanup failed at \(path) after \(originalStage.rawValue)."
        case .readFailed(let path):
            "The release artifact could not be read at \(path)."
        case .readBudgetExceeded(let path):
            "The release artifact read exceeded its admitted budget at \(path)."
        case .readIntegrityFailed(let path):
            "The release artifact identity or immutable snapshot changed at \(path)."
        case .readCancelled(let path):
            "The release artifact read was cancelled at \(path)."
        case .readCleanupFailed(let path, let primaryReason, let closeReason):
            if let primaryReason {
                "Release artifact cleanup failed at \(path) after read failure \(primaryReason): \(closeReason)"
            } else {
                "Release artifact cleanup failed at \(path): \(closeReason)"
            }
        }
    }
}
