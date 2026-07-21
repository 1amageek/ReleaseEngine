import Foundation
import PhysicalDesignCore
import CircuiteFoundation

/// Emits an exact standard-stream copy. Format conversion is deliberately delegated to a
/// separately qualified `LayoutStreamEncoding` implementation.
public struct ExactLayoutStreamEncoder: LayoutStreamEncoding {
    private let verifier: LocalArtifactVerifier

    public init(verifier: LocalArtifactVerifier = LocalArtifactVerifier()) {
        self.verifier = verifier
    }

    public func encode(
        _ source: PhysicalDesignReference,
        format: ArtifactFormat,
        relativeTo projectRoot: URL
    ) async throws -> Data {
        guard source.layoutArtifact.format == .gdsii || source.layoutArtifact.format == .oasis else {
            throw LayoutStreamEncodingError.unsupportedSourceFormat(source.layoutArtifact.format)
        }
        guard source.layoutArtifact.format == format else {
            throw LayoutStreamEncodingError.formatConversionRequiresQualifiedEncoder(
                source: source.layoutArtifact.format,
                destination: format
            )
        }
        let integrity = verifier.verify(source.layoutArtifact, relativeTo: projectRoot)
        guard integrity.isVerified else {
            throw LayoutStreamEncodingError.sourceArtifactIntegrityFailed(
                integrity.issues.map { $0.detail ?? $0.code.rawValue }
            )
        }
        do {
            let url = try source.layoutArtifact.locator.location.resolvedFileURL(relativeTo: projectRoot)
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch let error as LayoutStreamEncodingError {
            throw error
        } catch {
            throw LayoutStreamEncodingError.sourceArtifactUnreadable
        }
    }
}
