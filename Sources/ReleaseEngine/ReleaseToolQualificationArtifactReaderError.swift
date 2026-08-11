import CircuiteFoundation
import Foundation

enum ReleaseToolQualificationArtifactReaderError: Error, LocalizedError, Sendable {
    case bindingMissing(ArtifactID)

    var errorDescription: String? {
        switch self {
        case .bindingMissing(let artifactID):
            "Release qualification evidence has no exact binding for \(artifactID)."
        }
    }
}
