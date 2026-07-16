import Foundation
import CircuiteFoundation

/// Creates canonical Foundation artifact references for release test fixtures.
func makeTestArtifactReference(
    artifactID: String? = nil,
    path: String,
    kind: ArtifactKind,
    format: ArtifactFormat,
    role: ArtifactRole = .input,
    sha256: String? = nil,
    byteCount: Int64? = nil,
    producer: ProducerIdentity? = nil
) -> ArtifactReference {
    do {
        let location = try ArtifactLocation(workspaceRelativePath: path)
        let digest = try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: sha256 ?? String(repeating: "0", count: 64)
        )
        let identifier: ArtifactID?
        if let artifactID {
            identifier = try ArtifactID(rawValue: artifactID)
        } else {
            identifier = nil
        }
        return ArtifactReference(
            id: identifier,
            locator: ArtifactLocator(
                location: location,
                role: role,
                kind: kind,
                format: format
            ),
            digest: digest,
            byteCount: UInt64(max(0, byteCount ?? 0)),
            producer: producer
        )
    } catch {
        preconditionFailure("Invalid release test artifact fixture: \(error)")
    }
}

extension SHA256ContentDigester {
    func sha256(data: Data) -> String {
        do {
            return try digest(data: data).hexadecimalValue
        } catch {
            preconditionFailure("SHA-256 is unavailable in the release fixture: \(error)")
        }
    }
}
