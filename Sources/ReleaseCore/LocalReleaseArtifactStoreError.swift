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
        }
    }
}
