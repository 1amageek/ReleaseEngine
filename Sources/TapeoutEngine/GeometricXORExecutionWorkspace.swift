import CircuiteFoundation
import Foundation

struct GeometricXORExecutionWorkspace {
    let directoryURL: URL
    let executable: ArtifactReference
    let executableURL: URL
    let source: ArtifactReference
    let sourceURL: URL
    let streamed: ArtifactReference
    let streamedURL: URL
    let reportURL: URL

    static func create(
        executable: ArtifactReference,
        executableURL: URL,
        source: ArtifactReference,
        sourceURL: URL,
        streamed: ArtifactReference,
        streamedURL: URL,
        verifier: LocalArtifactVerifier
    ) throws -> Self {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("release-layout-xor-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        do {
            let executableSnapshot = try snapshot(
                executable,
                sourceURL: executableURL,
                destinationURL: directoryURL.appendingPathComponent("qualified-xor-tool"),
                permissions: 0o500,
                verifier: verifier
            )
            let sourceSnapshot = try snapshot(
                source,
                sourceURL: sourceURL,
                destinationURL: directoryURL.appendingPathComponent(
                    "source.\(source.locator.format.rawValue)"
                ),
                permissions: 0o400,
                verifier: verifier
            )
            let streamedSnapshot = try snapshot(
                streamed,
                sourceURL: streamedURL,
                destinationURL: directoryURL.appendingPathComponent(
                    "streamed.\(streamed.locator.format.rawValue)"
                ),
                permissions: 0o400,
                verifier: verifier
            )
            return Self(
                directoryURL: directoryURL,
                executable: executableSnapshot,
                executableURL: directoryURL.appendingPathComponent("qualified-xor-tool"),
                source: sourceSnapshot,
                sourceURL: directoryURL.appendingPathComponent(
                    "source.\(source.locator.format.rawValue)"
                ),
                streamed: streamedSnapshot,
                streamedURL: directoryURL.appendingPathComponent(
                    "streamed.\(streamed.locator.format.rawValue)"
                ),
                reportURL: directoryURL.appendingPathComponent("report.json")
            )
        } catch {
            do {
                try fileManager.removeItem(at: directoryURL)
            } catch {
                throw GeometricXORExecutionWorkspaceError.cleanupFailed
            }
            throw error
        }
    }

    func verify(using verifier: LocalArtifactVerifier) -> Bool {
        verifier.verify(executable).isVerified
            && verifier.verify(source).isVerified
            && verifier.verify(streamed).isVerified
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directoryURL)
    }

    private static func snapshot(
        _ reference: ArtifactReference,
        sourceURL: URL,
        destinationURL: URL,
        permissions: Int,
        verifier: LocalArtifactVerifier
    ) throws -> ArtifactReference {
        // A physical copy is required here: execution must not observe mutations to
        // the caller-owned artifact after its digest has been accepted.
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: destinationURL.path
        )
        let snapshot = ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(fileURL: destinationURL),
                role: reference.locator.role,
                kind: reference.locator.kind,
                format: reference.locator.format
            ),
            digest: reference.digest,
            byteCount: reference.byteCount,
            producer: reference.producer
        )
        guard verifier.verify(snapshot).isVerified else {
            throw GeometricXORExecutionWorkspaceError.snapshotIntegrityFailed
        }
        return snapshot
    }
}

enum GeometricXORExecutionWorkspaceError: Error {
    case snapshotIntegrityFailed
    case cleanupFailed
}
