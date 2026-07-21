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
        pdkDigest: String,
        projectRoot: URL?
    ) async -> LayoutXORResult {
        guard let projectRoot else {
            return LayoutXORResult(
                status: .blocked,
                method: .byteIdentity,
                sourceDigest: source.digest.hexadecimalValue,
                streamedDigest: streamed.digest.hexadecimalValue,
                message: "A project root is required for exact-stream comparison."
            )
        }
        let sourceIntegrity = verifier.verify(source, relativeTo: projectRoot)
        let streamedIntegrity = verifier.verify(streamed, relativeTo: projectRoot)
        guard sourceIntegrity.isVerified, streamedIntegrity.isVerified else {
            return LayoutXORResult(
                status: .blocked,
                method: .byteIdentity,
                sourceDigest: source.digest.hexadecimalValue,
                streamedDigest: streamed.digest.hexadecimalValue,
                message: "Exact-stream comparison is blocked until both layout artifacts pass integrity verification."
            )
        }
        let sourceDigest = source.digest.hexadecimalValue
        let streamedDigest = streamed.digest.hexadecimalValue
        if sourceDigest == streamedDigest {
            return LayoutXORResult(
                status: .passed,
                method: .byteIdentity,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "Source and streamed layout bytes are identical."
            )
        }
        return LayoutXORResult(
            status: .failed,
            method: .byteIdentity,
            sourceDigest: sourceDigest,
            streamedDigest: streamedDigest,
            message: "Source and streamed layout bytes differ. Geometric XOR equivalence requires a qualified geometry comparator."
        )
    }
}
