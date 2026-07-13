import Foundation
import ReleaseCore
import CircuiteFoundation

public struct DefaultLayoutXORComparator: LayoutXORComparing {
    private let verifier: LocalArtifactVerifier

    public init(verifier: LocalArtifactVerifier = LocalArtifactVerifier()) {
        self.verifier = verifier
    }

    public func compare(
        source: ArtifactReference,
        streamed: ArtifactReference,
        projectRoot: URL?
    ) -> LayoutXORResult {
        guard let projectRoot else {
            return LayoutXORResult(
                status: .blocked,
                method: "bytewise-exact-stream",
                sourceDigest: source.sha256,
                streamedDigest: streamed.sha256,
                message: "A project root is required for exact-stream comparison."
            )
        }
        let sourceIntegrity = verifier.verify(source, relativeTo: projectRoot)
        let streamedIntegrity = verifier.verify(streamed, relativeTo: projectRoot)
        guard sourceIntegrity.isVerified, streamedIntegrity.isVerified else {
            return LayoutXORResult(
                status: .blocked,
                method: "bytewise-exact-stream",
                sourceDigest: source.sha256,
                streamedDigest: streamed.sha256,
                message: "Exact-stream comparison is blocked until both layout artifacts pass integrity verification."
            )
        }
        let sourceDigest = source.sha256
        let streamedDigest = streamed.sha256
        if sourceDigest == streamedDigest {
            return LayoutXORResult(
                status: .passed,
                method: "bytewise-exact-stream",
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "Source and streamed layout bytes are identical."
            )
        }
        return LayoutXORResult(
            status: .failed,
            method: "bytewise-exact-stream",
            sourceDigest: sourceDigest,
            streamedDigest: streamedDigest,
            message: "Source and streamed layout bytes differ. Geometric XOR equivalence requires a qualified geometry comparator."
        )
    }
}
