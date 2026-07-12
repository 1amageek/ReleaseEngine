import Foundation
import ReleaseCore
import XcircuitePackage

public struct DefaultLayoutXORComparator: LayoutXORComparing {
    private let verifier: XcircuiteFileReferenceVerifier

    public init(verifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()) {
        self.verifier = verifier
    }

    public func compare(
        source: XcircuiteFileReference,
        streamed: XcircuiteFileReference,
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
        let sourceIntegrity = verifier.verify(source, projectRoot: projectRoot)
        let streamedIntegrity = verifier.verify(streamed, projectRoot: projectRoot)
        guard sourceIntegrity.status == .verified, streamedIntegrity.status == .verified else {
            return LayoutXORResult(
                status: .blocked,
                method: "bytewise-exact-stream",
                sourceDigest: sourceIntegrity.actualSHA256,
                streamedDigest: streamedIntegrity.actualSHA256,
                message: "Exact-stream comparison is blocked until both layout artifacts pass integrity verification."
            )
        }
        let sourceDigest = sourceIntegrity.actualSHA256
        let streamedDigest = streamedIntegrity.actualSHA256
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
