import CircuiteFoundation
import CircuiteFoundationCrypto
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
        executableData: Data,
        source: ArtifactReference,
        sourceData: Data,
        streamed: ArtifactReference,
        streamedData: Data
    ) throws -> Self {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("release-layout-xor-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)

        let executableURL = directoryURL.appendingPathComponent("qualified-xor-tool")
        let sourceURL = directoryURL.appendingPathComponent(
            "source.\(source.descriptor.format.rawValue)"
        )
        let streamedURL = directoryURL.appendingPathComponent(
            "streamed.\(streamed.descriptor.format.rawValue)"
        )
        do {
            try snapshot(
                executableData,
                matching: executable,
                destinationURL: executableURL,
                permissions: 0o500
            )
            try snapshot(
                sourceData,
                matching: source,
                destinationURL: sourceURL,
                permissions: 0o400
            )
            try snapshot(
                streamedData,
                matching: streamed,
                destinationURL: streamedURL,
                permissions: 0o400
            )
            return Self(
                directoryURL: directoryURL,
                executable: executable,
                executableURL: executableURL,
                source: source,
                sourceURL: sourceURL,
                streamed: streamed,
                streamedURL: streamedURL,
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

    func verify() -> Bool {
        Self.matches(executable, at: executableURL)
            && Self.matches(source, at: sourceURL)
            && Self.matches(streamed, at: streamedURL)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: directoryURL)
    }

    private static func snapshot(
        _ data: Data,
        matching reference: ArtifactReference,
        destinationURL: URL,
        permissions: Int
    ) throws {
        // A physical copy is required here: execution must not observe mutations to
        // caller-owned materializations after their content identities were admitted.
        guard matches(reference, data: data) else {
            throw GeometricXORExecutionWorkspaceError.snapshotIntegrityFailed
        }
        try data.write(to: destinationURL, options: .withoutOverwriting)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: destinationURL.path
        )
        guard matches(reference, at: destinationURL) else {
            throw GeometricXORExecutionWorkspaceError.snapshotIntegrityFailed
        }
    }

    private static func matches(
        _ reference: ArtifactReference,
        at url: URL
    ) -> Bool {
        do {
            return matches(reference, data: try Data(contentsOf: url, options: .mappedIfSafe))
        } catch {
            return false
        }
    }

    private static func matches(
        _ reference: ArtifactReference,
        data: Data
    ) -> Bool {
        do {
            let digest = try SHA256ContentDigester().digest(data: data)
            return reference.byteCount == UInt64(data.count)
                && reference.digest == digest
        } catch {
            return false
        }
    }
}

enum GeometricXORExecutionWorkspaceError: Error {
    case snapshotIntegrityFailed
    case cleanupFailed
}
