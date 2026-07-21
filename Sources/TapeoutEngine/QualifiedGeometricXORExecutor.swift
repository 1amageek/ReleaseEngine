import Foundation
import CircuiteFoundation
import ReleaseCore
import SignoffToolSupport
import ToolQualification

public struct QualifiedGeometricXORExecutor: LayoutXORComparing {
    private let configuration: GeometricXORToolConfiguration
    private let artifactPersister: any ReleaseArtifactPersisting
    private let verifier: LocalArtifactVerifier
    private let digester: SHA256ContentDigester
    private let processRunner: any TimedProcessRunning
    private let now: @Sendable () -> Date

    public init(
        configuration: GeometricXORToolConfiguration,
        artifactPersister: any ReleaseArtifactPersisting = LocalReleaseArtifactStore(),
        verifier: LocalArtifactVerifier = LocalArtifactVerifier(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.artifactPersister = artifactPersister
        self.verifier = verifier
        self.digester = SHA256ContentDigester()
        self.processRunner = TimedProcessRunner(timeoutSeconds: configuration.timeoutSeconds)
        self.now = now
    }

    public init(
        configuration: GeometricXORToolConfiguration,
        artifactPersister: any ReleaseArtifactPersisting,
        processRunner: any TimedProcessRunning,
        verifier: LocalArtifactVerifier = LocalArtifactVerifier(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.artifactPersister = artifactPersister
        self.verifier = verifier
        self.digester = SHA256ContentDigester()
        self.processRunner = processRunner
        self.now = now
    }

    public func compare(
        source: ArtifactReference,
        streamed: ArtifactReference,
        pdkDigest: String,
        projectRoot: URL?
    ) async -> LayoutXORResult {
        let startedAt = now()
        let qualification = configuration.qualification
        let sourceDigest = source.digest.hexadecimalValue
        let streamedDigest = streamed.digest.hexadecimalValue

        guard let projectRoot else {
            return result(
                status: .blocked,
                executionStatus: .notExecuted,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "A project root is required for qualified geometric XOR."
            )
        }
        guard Self.isStandardLayout(source), Self.isStandardLayout(streamed) else {
            return result(
                status: .blocked,
                executionStatus: .notExecuted,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "Qualified geometric XOR accepts only GDSII or OASIS layout artifacts."
            )
        }
        guard verifier.verify(source, relativeTo: projectRoot).isVerified,
              verifier.verify(streamed, relativeTo: projectRoot).isVerified else {
            return result(
                status: .blocked,
                executionStatus: .notExecuted,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "Qualified geometric XOR requires integrity-verified input layouts."
            )
        }
        guard qualification.isQualified(at: startedAt, requirePDKScope: true) else {
            return result(
                status: .blocked,
                executionStatus: .unqualified,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "The configured geometric XOR process is not production-qualified."
            )
        }
        guard qualification.scope.pdkDigest?
            .caseInsensitiveCompare(pdkDigest) == .orderedSame else {
            return result(
                status: .blocked,
                executionStatus: .unqualified,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "The qualified geometric XOR scope does not match the requested PDK digest."
            )
        }

        let executableArtifact = qualification.identityArtifacts.toolExecutable
        guard let producer = executableArtifact.producer,
              producer.kind == .tool,
              producer.identifier == qualification.scope.implementationID,
              producer.version == qualification.scope.toolVersion,
              executableArtifact.digest.hexadecimalValue.caseInsensitiveCompare(
                qualification.scope.binaryDigest
              ) == .orderedSame,
              verifier.verify(executableArtifact, relativeTo: projectRoot).isVerified else {
            return result(
                status: .blocked,
                executionStatus: .unqualified,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "The qualified executable identity does not match its retained artifact."
            )
        }

        let executableURL: URL
        let sourceURL: URL
        let streamedURL: URL
        do {
            executableURL = try executableArtifact.locator.location.resolvedFileURL(relativeTo: projectRoot)
            sourceURL = try source.locator.location.resolvedFileURL(relativeTo: projectRoot)
            streamedURL = try streamed.locator.location.resolvedFileURL(relativeTo: projectRoot)
        } catch {
            return result(
                status: .blocked,
                executionStatus: .notExecuted,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "A geometric XOR input or executable path is invalid."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return result(
                status: .blocked,
                executionStatus: .unqualified,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "The qualified geometric XOR artifact is not executable."
            )
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-layout-xor-\(UUID().uuidString)", isDirectory: true)
        let temporaryReportURL = temporaryDirectory.appendingPathComponent("report.json")
        do {
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: false
            )
        } catch {
            return result(
                status: .blocked,
                executionStatus: .artifactPersistenceFailed,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "A private temporary workspace for geometric XOR could not be created."
            )
        }

        let arguments = configuration.arguments + [
            "--source-layout", sourceURL.path,
            "--streamed-layout", streamedURL.path,
            "--report", temporaryReportURL.path,
        ]
        let invocation: ExecutionInvocation
        let environmentFingerprint: ExecutionEnvironmentFingerprint
        do {
            invocation = try ExecutionInvocation.externalProcess(
                executable: executableURL.path,
                arguments: arguments,
                workingDirectory: projectRoot.path
            )
            environmentFingerprint = try makeEnvironmentFingerprint()
        } catch {
            return cleanupFailureOrResult(
                temporaryDirectory: temporaryDirectory,
                fallback: result(
                    status: .blocked,
                    executionStatus: .notExecuted,
                    sourceDigest: sourceDigest,
                    streamedDigest: streamedDigest,
                    message: "Geometric XOR invocation provenance is invalid."
                ),
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest
            )
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = configuration.environment
        process.currentDirectoryURL = projectRoot

        let processResult: TimedProcessResult
        do {
            processResult = try await processRunner.run(process: process, cancellationCheck: {
                Task.isCancelled
            })
        } catch let error as TimedProcessError {
            return cleanupFailureOrResult(
                temporaryDirectory: temporaryDirectory,
                fallback: processFailureResult(
                    error,
                    sourceDigest: sourceDigest,
                    streamedDigest: streamedDigest
                ),
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest
            )
        } catch {
            return cleanupFailureOrResult(
                temporaryDirectory: temporaryDirectory,
                fallback: result(
                    status: .blocked,
                    executionStatus: .launchFailed,
                    sourceDigest: sourceDigest,
                    streamedDigest: streamedDigest,
                    message: "The qualified geometric XOR process could not be executed."
                ),
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest
            )
        }

        guard processResult.exitCode == 0 else {
            return cleanupFailureOrResult(
                temporaryDirectory: temporaryDirectory,
                fallback: result(
                    status: .failed,
                    executionStatus: .exitedWithFailure,
                    sourceDigest: sourceDigest,
                    streamedDigest: streamedDigest,
                    message: "The qualified geometric XOR process exited unsuccessfully.",
                    exitCode: processResult.exitCode
                ),
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest
            )
        }

        let reportData: Data
        let report: LayoutXORReport
        do {
            reportData = try Data(contentsOf: temporaryReportURL, options: .mappedIfSafe)
            report = try JSONDecoder().decode(LayoutXORReport.self, from: reportData)
            guard try report.canonicalData() == reportData else {
                throw LayoutXORReportError.nonCanonicalEncoding
            }
        } catch {
            return cleanupFailureOrResult(
                temporaryDirectory: temporaryDirectory,
                fallback: result(
                    status: .blocked,
                    executionStatus: .invalidReport,
                    sourceDigest: sourceDigest,
                    streamedDigest: streamedDigest,
                    message: "The geometric XOR tool did not produce a canonical typed report.",
                    exitCode: processResult.exitCode
                ),
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest
            )
        }

        do {
            try FileManager.default.removeItem(at: temporaryDirectory)
        } catch {
            return result(
                status: .blocked,
                executionStatus: .artifactPersistenceFailed,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "The private geometric XOR workspace could not be removed.",
                exitCode: processResult.exitCode
            )
        }

        guard verifier.verify(executableArtifact, relativeTo: projectRoot).isVerified else {
            return result(
                status: .blocked,
                executionStatus: .unqualified,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "The qualified geometric XOR executable changed during execution.",
                exitCode: processResult.exitCode
            )
        }

        do {
            let reportDigest = try digester.digest(data: reportData)
            let evidence = try await artifactPersister.persist(
                ReleaseArtifactPersistenceRequest(
                    locator: configuration.reportOutput,
                    bytes: reportData,
                    producer: producer
                ),
                relativeTo: projectRoot
            )
            let retainedReport = try await artifactPersister.load(evidence, relativeTo: projectRoot)
            guard evidence.digest == reportDigest,
                  evidence.byteCount == UInt64(reportData.count),
                  evidence.producer == producer,
                  retainedReport == reportData else {
                return result(
                    status: .blocked,
                    executionStatus: .artifactPersistenceFailed,
                    sourceDigest: sourceDigest,
                    streamedDigest: streamedDigest,
                    message: "Persisted geometric XOR evidence failed read-back verification.",
                    exitCode: processResult.exitCode
                )
            }
            let provenance = try ExecutionProvenance(
                producer: producer,
                inputs: [source, streamed],
                invocation: invocation,
                environment: environmentFingerprint,
                startedAt: startedAt,
                completedAt: now()
            )
            let hasDifferences = report.differenceCount != 0
                || report.differenceAreaSquareMicrometers != 0
            return LayoutXORResult(
                status: hasDifferences ? .failed : .passed,
                method: .geometricXOR,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: hasDifferences
                    ? "Geometric XOR found layout differences."
                    : "Qualified geometric XOR found no layout differences.",
                evidenceArtifact: evidence,
                processQualification: qualification,
                executionStatus: .completed,
                exitCode: processResult.exitCode,
                differenceCount: report.differenceCount,
                differenceAreaSquareMicrometers: report.differenceAreaSquareMicrometers,
                rawReportDigest: reportDigest,
                provenance: provenance
            )
        } catch {
            return result(
                status: .blocked,
                executionStatus: .artifactPersistenceFailed,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "Geometric XOR evidence could not be persisted or provenanced.",
                exitCode: processResult.exitCode
            )
        }
    }

    private func makeEnvironmentFingerprint() throws -> ExecutionEnvironmentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = try digester.digest(data: encoder.encode(configuration.environment))
        return try ExecutionEnvironmentFingerprint(
            platform: Self.platform,
            architecture: Self.architecture,
            toolchain: "external-process",
            environmentDigest: digest
        )
    }

    private func processFailureResult(
        _ error: TimedProcessError,
        sourceDigest: String,
        streamedDigest: String
    ) -> LayoutXORResult {
        let executionStatus: LayoutXORExecutionStatus
        switch error {
        case .timedOut:
            executionStatus = .timedOut
        case .cancelled:
            executionStatus = .cancelled
        case .launchFailed:
            executionStatus = .launchFailed
        case .invalidConfiguration, .cancellationCheckFailed:
            executionStatus = .launchFailed
        }
        return result(
            status: .blocked,
            executionStatus: executionStatus,
            sourceDigest: sourceDigest,
            streamedDigest: streamedDigest,
            message: error.localizedDescription
        )
    }

    private func cleanupFailureOrResult(
        temporaryDirectory: URL,
        fallback: LayoutXORResult,
        sourceDigest: String,
        streamedDigest: String
    ) -> LayoutXORResult {
        do {
            try FileManager.default.removeItem(at: temporaryDirectory)
            return fallback
        } catch {
            return result(
                status: .blocked,
                executionStatus: .artifactPersistenceFailed,
                sourceDigest: sourceDigest,
                streamedDigest: streamedDigest,
                message: "The private geometric XOR workspace could not be removed."
            )
        }
    }

    private func result(
        status: LayoutXORStatus,
        executionStatus: LayoutXORExecutionStatus,
        sourceDigest: String,
        streamedDigest: String,
        message: String,
        exitCode: Int32? = nil
    ) -> LayoutXORResult {
        LayoutXORResult(
            status: status,
            method: .geometricXOR,
            sourceDigest: sourceDigest,
            streamedDigest: streamedDigest,
            message: message,
            processQualification: configuration.qualification,
            executionStatus: executionStatus,
            exitCode: exitCode
        )
    }

    private static func isStandardLayout(_ artifact: ArtifactReference) -> Bool {
        artifact.kind == .layout && (artifact.format == .gdsii || artifact.format == .oasis)
    }

    private static var platform: String {
        #if os(macOS)
        "macos"
        #elseif os(Linux)
        "linux"
        #else
        "unknown-platform"
        #endif
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86-64"
        #else
        "unknown-architecture"
        #endif
    }
}
