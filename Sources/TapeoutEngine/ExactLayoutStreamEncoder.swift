import Foundation
import PhysicalDesignCore
import CircuiteFoundation
import ReleaseCore

/// Emits an exact standard-stream copy. Format conversion is deliberately delegated to a
/// separately qualified `LayoutStreamEncoding` implementation.
public struct ExactLayoutStreamEncoder: LayoutStreamEncoding {
    private let artifactReader: any ReleaseArtifactReading

    public init(
        artifactReader: any ReleaseArtifactReading = LocalReleaseArtifactStore()
    ) {
        self.artifactReader = artifactReader
    }

    public func encode(
        _ source: PhysicalDesignReference,
        format: ArtifactFormat,
        relativeTo projectRoot: URL
    ) async throws -> Data {
        let sourceFormat = source.layoutArtifact.descriptor.format
        guard sourceFormat == .gdsii || sourceFormat == .oasis else {
            throw LayoutStreamEncodingError.unsupportedSourceFormat(sourceFormat)
        }
        guard sourceFormat == format else {
            throw LayoutStreamEncodingError.formatConversionRequiresQualifiedEncoder(
                source: sourceFormat,
                destination: format
            )
        }
        do {
            let binding = try ReleaseArtifactBinding(
                logicalID: source.layoutArtifact.logicalID,
                reference: source.layoutArtifact.reference,
                availability: source.layoutArtifact.availability
            )
            return try await artifactReader.load(binding, relativeTo: projectRoot)
        } catch let error as LayoutStreamEncodingError {
            throw error
        } catch {
            throw LayoutStreamEncodingError.sourceArtifactUnreadable
        }
    }
}
