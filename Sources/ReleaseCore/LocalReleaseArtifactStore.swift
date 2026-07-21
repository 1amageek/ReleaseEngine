import Foundation
import CircuiteFoundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A project-relative immutable artifact store for standalone use.
public actor LocalReleaseArtifactStore: ReleaseArtifactPersisting {
    public init() {}

    public func persist(
        _ request: ReleaseArtifactPersistenceRequest,
        relativeTo projectRoot: URL
    ) async throws -> ArtifactReference {
        guard request.locator.location.storage == .workspaceRelative else {
            throw LocalReleaseArtifactStoreError.invalidLocation(request.locator.location.value)
        }
        let digest: ContentDigest
        do {
            digest = try SHA256ContentDigester().digest(data: request.bytes)
        } catch {
            throw LocalReleaseArtifactStoreError.writeFailed(
                path: request.locator.location.value,
                stage: .contentWrite
            )
        }
        try persistAtomically(
            request.bytes,
            path: request.locator.location.value,
            projectRoot: projectRoot
        )
        return ArtifactReference(
            locator: request.locator,
            digest: digest,
            byteCount: UInt64(request.bytes.count),
            producer: request.producer
        )
    }

    public func load(
        _ artifact: ArtifactReference,
        relativeTo projectRoot: URL
    ) async throws -> Data {
        guard artifact.locator.location.storage == .workspaceRelative else {
            throw LocalReleaseArtifactStoreError.invalidLocation(artifact.locator.location.value)
        }
        do {
            let data = try readSecurely(
                path: artifact.path,
                expectedByteCount: artifact.byteCount,
                projectRoot: projectRoot
            )
            guard artifact.byteCount == UInt64(data.count),
                  try SHA256ContentDigester().digest(data: data) == artifact.digest else {
                throw LocalReleaseArtifactStoreError.readFailed(artifact.path)
            }
            return data
        } catch let error as LocalReleaseArtifactStoreError {
            throw error
        } catch {
            throw LocalReleaseArtifactStoreError.readFailed(artifact.path)
        }
    }

    private func persistAtomically(_ data: Data, path: String, projectRoot: URL) throws {
        let parent = try openParentDirectory(path: path, projectRoot: projectRoot, create: true)
        defer { systemClose(parent.descriptor) }
        let temporaryName = ".\(parent.fileName).\(UUID().uuidString).tmp"
        let temporaryDescriptor = temporaryName.withCString {
            systemOpenAt(
                parent.descriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                0o600
            )
        }
        guard temporaryDescriptor >= 0 else {
            throw LocalReleaseArtifactStoreError.writeFailed(path: path, stage: .contentWrite)
        }
        var temporaryExists = true
        let outcome: Result<Void, Error>
        do {
            guard writeAll(data, to: temporaryDescriptor) else {
                throw LocalReleaseArtifactStoreError.writeFailed(path: path, stage: .contentWrite)
            }
            guard systemFChmod(temporaryDescriptor, 0o444) == 0 else {
                throw LocalReleaseArtifactStoreError.writeFailed(path: path, stage: .permissionUpdate)
            }
            guard systemFSync(temporaryDescriptor) == 0 else {
                throw LocalReleaseArtifactStoreError.writeFailed(path: path, stage: .fileSynchronization)
            }
            let linkResult = temporaryName.withCString { temporaryPointer in
                parent.fileName.withCString { filePointer in
                    systemLinkAt(parent.descriptor, temporaryPointer, parent.descriptor, filePointer)
                }
            }
            guard linkResult == 0 else {
                if systemErrno == EEXIST {
                    throw LocalReleaseArtifactStoreError.targetAlreadyExists(path)
                }
                throw LocalReleaseArtifactStoreError.writeFailed(path: path, stage: .publication)
            }
            let temporaryUnlink = temporaryName.withCString {
                systemUnlinkAt(parent.descriptor, $0)
            }
            guard temporaryUnlink == 0 else {
                let rollback = parent.fileName.withCString {
                    systemUnlinkAt(parent.descriptor, $0)
                }
                guard rollback == 0, systemFSync(parent.descriptor) == 0 else {
                    throw LocalReleaseArtifactStoreError.cleanupFailed(
                        path: path,
                        originalStage: .publication
                    )
                }
                throw LocalReleaseArtifactStoreError.cleanupFailed(
                    path: path,
                    originalStage: .publication
                )
            }
            temporaryExists = false
            guard systemFSync(parent.descriptor) == 0 else {
                let rollback = parent.fileName.withCString {
                    systemUnlinkAt(parent.descriptor, $0)
                }
                guard rollback == 0, systemFSync(parent.descriptor) == 0 else {
                    throw LocalReleaseArtifactStoreError.cleanupFailed(
                        path: path,
                        originalStage: .directorySynchronization
                    )
                }
                throw LocalReleaseArtifactStoreError.writeFailed(
                    path: path,
                    stage: .directorySynchronization
                )
            }
            outcome = .success(())
        } catch {
            outcome = .failure(error)
        }
        systemClose(temporaryDescriptor)
        if temporaryExists {
            let cleanupResult = temporaryName.withCString {
                systemUnlinkAt(parent.descriptor, $0)
            }
            if cleanupResult != 0 {
                throw LocalReleaseArtifactStoreError.cleanupFailed(
                    path: path,
                    originalStage: failureStage(from: outcome)
                )
            }
        }
        try outcome.get()
    }

    private func failureStage(
        from outcome: Result<Void, Error>
    ) -> LocalReleaseArtifactStoreError.Stage {
        guard case .failure(let error) = outcome,
              let localError = error as? LocalReleaseArtifactStoreError else {
            return .contentWrite
        }
        switch localError {
        case .writeFailed(_, let stage), .cleanupFailed(_, let stage):
            return stage
        case .targetAlreadyExists:
            return .publication
        case .invalidLocation, .readFailed:
            return .contentWrite
        }
    }

    private func readSecurely(
        path: String,
        expectedByteCount: UInt64,
        projectRoot: URL
    ) throws -> Data {
        let parent = try openParentDirectory(path: path, projectRoot: projectRoot, create: false)
        defer { systemClose(parent.descriptor) }
        let descriptor = parent.fileName.withCString {
            systemOpenAt(parent.descriptor, $0, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW, 0)
        }
        guard descriptor >= 0 else {
            throw LocalReleaseArtifactStoreError.readFailed(path)
        }
        defer { systemClose(descriptor) }
        var status = stat()
        guard systemFStat(descriptor, &status) == 0,
              status.st_size >= 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              UInt64(status.st_size) == expectedByteCount,
              UInt64(status.st_size) <= UInt64(Int.max) else {
            throw LocalReleaseArtifactStoreError.readFailed(path)
        }
        var data = Data(count: Int(status.st_size))
        guard readAll(from: descriptor, into: &data) else {
            throw LocalReleaseArtifactStoreError.readFailed(path)
        }
        var trailingByte: UInt8 = 0
        let trailingCount = withUnsafeMutablePointer(to: &trailingByte) {
            systemRead(descriptor, $0, 1)
        }
        var finalStatus = stat()
        guard trailingCount == 0,
              systemFStat(descriptor, &finalStatus) == 0,
              finalStatus.st_size == status.st_size,
              (finalStatus.st_mode & S_IFMT) == S_IFREG else {
            throw LocalReleaseArtifactStoreError.readFailed(path)
        }
        return data
    }

    private func openParentDirectory(
        path: String,
        projectRoot: URL,
        create: Bool
    ) throws -> (descriptor: Int32, fileName: String) {
        guard projectRoot.isFileURL,
              projectRoot.path.hasPrefix("/") else {
            throw LocalReleaseArtifactStoreError.invalidLocation(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 1,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let fileName = components.last else {
            throw LocalReleaseArtifactStoreError.invalidLocation(path)
        }
        var descriptor = projectRoot.path.withCString {
            systemOpen($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW, 0)
        }
        guard descriptor >= 0 else {
            if isUnsafePathError(systemErrno) {
                throw LocalReleaseArtifactStoreError.invalidLocation(path)
            }
            if create {
                throw LocalReleaseArtifactStoreError.writeFailed(path: path, stage: .directoryCreation)
            }
            throw LocalReleaseArtifactStoreError.readFailed(path)
        }
        for component in components.dropLast() {
            if create {
                let result = component.withCString {
                    systemMkdirAt(descriptor, $0, 0o755)
                }
                if result != 0 && systemErrno != EEXIST {
                    systemClose(descriptor)
                    throw LocalReleaseArtifactStoreError.writeFailed(path: path, stage: .directoryCreation)
                }
            }
            let next = component.withCString {
                systemOpenAt(descriptor, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW, 0)
            }
            guard next >= 0 else {
                let error = systemErrno
                systemClose(descriptor)
                if isUnsafePathError(error) {
                    throw LocalReleaseArtifactStoreError.invalidLocation(path)
                }
                if create {
                    throw LocalReleaseArtifactStoreError.writeFailed(path: path, stage: .directoryCreation)
                }
                throw LocalReleaseArtifactStoreError.readFailed(path)
            }
            systemClose(descriptor)
            descriptor = next
        }
        return (descriptor, fileName)
    }

    private func isUnsafePathError(_ value: Int32) -> Bool {
        value == ELOOP || value == ENOTDIR
    }

    private func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return buffer.isEmpty }
            var offset = 0
            while offset < buffer.count {
                let written = systemWrite(descriptor, base.advanced(by: offset), buffer.count - offset)
                if written < 0 {
                    if systemErrno == EINTR { continue }
                    return false
                }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    private func readAll(from descriptor: Int32, into data: inout Data) -> Bool {
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return buffer.isEmpty }
            var offset = 0
            while offset < buffer.count {
                let count = systemRead(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0 {
                    if systemErrno == EINTR { continue }
                    return false
                }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }
}

private var systemErrno: Int32 {
    errno
}

private func systemOpen(_ path: UnsafePointer<CChar>, _ flags: Int32, _ mode: mode_t) -> Int32 {
    open(path, flags, mode)
}

private func systemOpenAt(
    _ descriptor: Int32,
    _ path: UnsafePointer<CChar>,
    _ flags: Int32,
    _ mode: mode_t
) -> Int32 {
    openat(descriptor, path, flags, mode)
}

private func systemMkdirAt(_ descriptor: Int32, _ path: UnsafePointer<CChar>, _ mode: mode_t) -> Int32 {
    mkdirat(descriptor, path, mode)
}

private func systemLinkAt(
    _ oldDescriptor: Int32,
    _ oldPath: UnsafePointer<CChar>,
    _ newDescriptor: Int32,
    _ newPath: UnsafePointer<CChar>
) -> Int32 {
    linkat(oldDescriptor, oldPath, newDescriptor, newPath, 0)
}

private func systemUnlinkAt(_ descriptor: Int32, _ path: UnsafePointer<CChar>) -> Int32 {
    unlinkat(descriptor, path, 0)
}

private func systemWrite(_ descriptor: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
    write(descriptor, buffer, count)
}

private func systemRead(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
    read(descriptor, buffer, count)
}

private func systemFSync(_ descriptor: Int32) -> Int32 {
    fsync(descriptor)
}

private func systemFChmod(_ descriptor: Int32, _ mode: mode_t) -> Int32 {
    fchmod(descriptor, mode)
}

private func systemFStat(_ descriptor: Int32, _ status: UnsafeMutablePointer<stat>) -> Int32 {
    fstat(descriptor, status)
}

private func systemClose(_ descriptor: Int32) {
    _ = close(descriptor)
}
