import Foundation
import ReleaseCore
import CircuiteFoundation

public struct DefaultLayoutXORComparator: LayoutXORComparing {
    private let artifactReader: any ReleaseArtifactReading

    public init(
        artifactReader: any ReleaseArtifactReading = LocalReleaseArtifactStore()
    ) {
        self.artifactReader = artifactReader
    }

    public func compare(
        source: ReleaseArtifactBinding,
        streamed: ReleaseArtifactBinding,
        pdkDigest: String,
        projectRoot: URL?
    ) async -> LayoutXORResult {
        guard let projectRoot else {
            return LayoutXORResult(
                status: .blocked,
                method: .byteIdentity,
                sourceDigest: source.reference.digest.hexadecimalValue,
                streamedDigest: streamed.reference.digest.hexadecimalValue,
                message: "A project root is required for exact-stream comparison."
            )
        }
        do {
            _ = try await artifactReader.load(source, relativeTo: projectRoot)
            _ = try await artifactReader.load(streamed, relativeTo: projectRoot)
        } catch {
            return LayoutXORResult(
                status: .blocked,
                method: .byteIdentity,
                sourceDigest: source.reference.digest.hexadecimalValue,
                streamedDigest: streamed.reference.digest.hexadecimalValue,
                message: "Exact-stream comparison is blocked until both layout artifacts pass integrity verification."
            )
        }
        let sourceDigest = source.reference.digest.hexadecimalValue
        let streamedDigest = streamed.reference.digest.hexadecimalValue
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
