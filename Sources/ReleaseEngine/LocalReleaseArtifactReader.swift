import CircuiteFoundation
import Foundation

public actor LocalReleaseArtifactReader: ReleaseArtifactReading {
    private let workspaceRoot: URL
    private let verifier: LocalArtifactVerifier

    public init(workspaceRoot: URL, verifier: LocalArtifactVerifier = LocalArtifactVerifier()) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.verifier = verifier
    }

    public func verifiedData(for reference: ArtifactReference) async throws -> Data {
        let integrity = verifier.verify(reference, relativeTo: workspaceRoot)
        guard integrity.isVerified else {
            throw ReleaseArtifactReadError.integrityFailure(
                integrity.issues.map { $0.detail ?? $0.code.rawValue }
            )
        }
        do {
            let url = try reference.locator.location.resolvedFileURL(relativeTo: workspaceRoot)
            return try Data(contentsOf: url)
        } catch {
            throw ReleaseArtifactReadError.unreadable(error.localizedDescription)
        }
    }
}
