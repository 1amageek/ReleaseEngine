import Foundation
import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem
import CircuiteFoundationFoundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A project-relative immutable artifact store for standalone use.
public actor LocalReleaseArtifactStore: ReleaseArtifactPersisting {
    public static let defaultReadBudget: ArtifactAccessBudget = {
        do {
            return try ArtifactAccessBudget(
                maximumPageByteCount: 1_048_576,
                maximumTotalByteCount: 1_073_741_824,
                maximumPageCount: 1_024,
                maximumWorkUnitCount: 4_096,
                maximumDurationNanoseconds: 60_000_000_000
            )
        } catch {
            preconditionFailure("The release artifact read budget is invalid: \(error)")
        }
    }()

    private let readBudget: ArtifactAccessBudget

    public init(
        readBudget: ArtifactAccessBudget = LocalReleaseArtifactStore.defaultReadBudget
    ) {
        self.readBudget = readBudget
    }

    public func persist(
        _ request: ReleaseArtifactPersistenceRequest,
        relativeTo projectRoot: URL
    ) async throws -> ReleaseArtifactBinding {
        let path = request.destination.relativePath.stringValue
        let digest: ContentDigest
        do {
            digest = try SHA256ContentDigester().digest(data: request.bytes)
        } catch {
            throw LocalReleaseArtifactStoreError.writeFailed(
                path: path,
                stage: .contentWrite
            )
        }
        try persistAtomically(
            request.bytes,
            path: path,
            projectRoot: projectRoot
        )
        let reference = try ArtifactReference(
            digest: digest,
            byteCount: UInt64(request.bytes.count),
            descriptor: request.destination.descriptor
        )
        return try ReleaseArtifactBinding(
            logicalID: request.logicalID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: request.destination.rootID,
                relativePath: request.destination.relativePath
            )
        )
    }

    public func load(
        _ artifact: ReleaseArtifactBinding,
        relativeTo projectRoot: URL
    ) async throws -> Data {
        guard case .local(_, let rootID, let relativePath) = artifact.availability else {
            throw LocalReleaseArtifactStoreError.invalidLocation(
                artifact.materializationDescription
            )
        }
        let path = relativePath.stringValue
        let access: ArtifactRootCapability
        do {
            access = try ArtifactRootCapability(
                rootID: rootID,
                directoryURL: projectRoot,
                digester: SHA256ContentDigester()
            )
        } catch {
            throw LocalReleaseArtifactStoreError.invalidLocation(path)
        }

        let data: Data
        do {
            data = try await read(
                artifact,
                path: path,
                using: access
            )
        } catch let primaryError {
            do {
                try await access.close().wait()
            } catch let closeError {
                throw LocalReleaseArtifactStoreError.readCleanupFailed(
                    path: path,
                    primaryReason: String(describing: primaryError),
                    closeReason: String(describing: closeError)
                )
            }
            if let localError = primaryError as? LocalReleaseArtifactStoreError {
                throw localError
            }
            throw LocalReleaseArtifactStoreError.readFailed(path)
        }
        do {
            try await access.close().wait()
        } catch {
            throw LocalReleaseArtifactStoreError.readCleanupFailed(
                path: path,
                primaryReason: nil,
                closeReason: String(describing: error)
            )
        }
        return data
    }

    private func read(
        _ artifact: ReleaseArtifactBinding,
        path: String,
        using access: ArtifactRootCapability
    ) async throws -> Data {
        let intent: ArtifactAccessIntent
        do {
            intent = try ArtifactAccessIntent(
                expectedReference: artifact.reference,
                availability: artifact.availability,
                operation: .read,
                budget: readBudget
            )
        } catch {
            throw LocalReleaseArtifactStoreError.invalidLocation(path)
        }

        let session: any ArtifactReadSession
        do {
            session = try await access.open(intent)
        } catch let accessError {
            throw Self.mapAccessError(accessError, path: path)
        }

        var data = Data()
        if artifact.reference.byteCount <= UInt64(Int.max) {
            data.reserveCapacity(Int(artifact.reference.byteCount))
        }
        do {
            var offset: UInt64 = 0
            while true {
                let page = try await session.readPage(
                    ArtifactReadPageRequest(
                        offset: offset,
                        maximumByteCount: readBudget.maximumPageByteCount
                    )
                )
                page.bytes.withUnsafeBytes { bytes in
                    data.append(contentsOf: bytes)
                }
                offset = page.cumulativeByteCount
                if page.completion == .complete {
                    guard page.finalReceipt?.observedArtifactID
                            == artifact.reference.id,
                          page.finalReceipt?.totalByteCount
                            == artifact.reference.byteCount else {
                        throw LocalReleaseArtifactStoreError.readIntegrityFailed(path)
                    }
                    break
                }
            }
        } catch let primaryError {
            do {
                _ = try await session.close().wait()
            } catch let closeError {
                throw LocalReleaseArtifactStoreError.readCleanupFailed(
                    path: path,
                    primaryReason: String(describing: primaryError),
                    closeReason: String(describing: closeError)
                )
            }
            if let localError = primaryError as? LocalReleaseArtifactStoreError {
                throw localError
            }
            if let accessError = primaryError as? ArtifactAccessError {
                throw Self.mapAccessError(accessError, path: path)
            }
            throw LocalReleaseArtifactStoreError.readFailed(path)
        }

        do {
            let receipt = try await session.close().wait()
            guard receipt.sessionIdentity == session.identity,
                  receipt.didReachTerminalPage else {
                throw LocalReleaseArtifactStoreError.readFailed(path)
            }
        } catch let localError as LocalReleaseArtifactStoreError {
            throw localError
        } catch {
            throw LocalReleaseArtifactStoreError.readCleanupFailed(
                path: path,
                primaryReason: nil,
                closeReason: String(describing: error)
            )
        }
        return data
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
        case .invalidLocation, .readFailed, .readBudgetExceeded,
                .readIntegrityFailed, .readCancelled, .readCleanupFailed:
            return .contentWrite
        }
    }

    private static func mapAccessError(
        _ error: ArtifactAccessError,
        path: String
    ) -> LocalReleaseArtifactStoreError {
        switch error {
        case .pageByteLimitExceeded, .totalByteLimitExceeded,
                .pageCountLimitExceeded, .workLimitExceeded,
                .deadlineExceeded:
            return .readBudgetExceeded(path)
        case .resourceGenerationChanged, .noncontiguousOffset,
                .truncatedResource, .byteCountMismatch,
                .contentDigestMismatch, .contentIdentityMismatch:
            return .readIntegrityFailed(path)
        case .cancelled:
            return .readCancelled(path)
        case .invalidIntent, .unsupportedCapability, .availabilityNotLocal,
                .rootMismatch, .invalidRoot, .symlinkTraversal,
                .nonRegularResource:
            return .invalidLocation(path)
        case .fileCloseFailed(let reason):
            return .readCleanupFailed(
                path: path,
                primaryReason: nil,
                closeReason: reason
            )
        case .cleanupFailed(let primary, let closeReason):
            return .readCleanupFailed(
                path: path,
                primaryReason: primary,
                closeReason: closeReason
            )
        case .openFailed, .metadataFailed, .resourceUnavailable,
                .readFailed, .sessionClosed:
            return .readFailed(path)
        }
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

private func systemFSync(_ descriptor: Int32) -> Int32 {
    fsync(descriptor)
}

private func systemFChmod(_ descriptor: Int32, _ mode: mode_t) -> Int32 {
    fchmod(descriptor, mode)
}

private func systemClose(_ descriptor: Int32) {
    _ = close(descriptor)
}
