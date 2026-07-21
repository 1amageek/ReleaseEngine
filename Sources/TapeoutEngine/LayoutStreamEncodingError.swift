import Foundation
import CircuiteFoundation

public enum LayoutStreamEncodingError: Error, Sendable, Hashable, LocalizedError {
    case unsupportedSourceFormat(ArtifactFormat)
    case formatConversionRequiresQualifiedEncoder(source: ArtifactFormat, destination: ArtifactFormat)
    case sourceArtifactIntegrityFailed([String])
    case sourceArtifactUnreadable

    public var errorDescription: String? {
        switch self {
        case .unsupportedSourceFormat(let format):
            "The source layout format \(format.rawValue) is not a standard tapeout stream."
        case .formatConversionRequiresQualifiedEncoder(let source, let destination):
            "Converting \(source.rawValue) to \(destination.rawValue) requires a qualified layout stream encoder."
        case .sourceArtifactIntegrityFailed(let issues):
            "The source layout artifact failed integrity verification: \(issues.joined(separator: "; "))."
        case .sourceArtifactUnreadable:
            "The source layout artifact could not be read."
        }
    }
}
