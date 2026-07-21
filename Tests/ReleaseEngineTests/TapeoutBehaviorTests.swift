import CircuiteFoundation
import DesignFlowKernel
import Foundation
import PDKCore
import PhysicalDesignCore
import ReleaseCore
import SignoffToolSupport
import TapeoutEngine
import Testing
import ToolQualification

@Suite("Tapeout behavior")
struct TapeoutBehaviorTests {
    @Test("byte identity is diagnostic evidence and cannot authorize tapeout")
    func byteIdentityDoesNotQualifyTapeout() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }

        let result = await DefaultLayoutXORComparator().compare(
            source: fixture.request.physicalDesign.layoutArtifact,
            streamed: fixture.request.physicalDesign.layoutArtifact,
            pdkDigest: fixture.request.pdk.digest,
            projectRoot: fixture.root
        )

        #expect(result.status == .passed)
        #expect(result.method == .byteIdentity)
        #expect(!result.isTapeoutQualified(at: fixture.generatedAt))
    }

    @Test("tapeout reproduces exact signoff, PDK, layout, stream-out, and handoff bindings")
    func exactBindings() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        let comparator = try await fixture.qualifiedComparator()

        let result = try await DefaultTapeoutPackaging(
            artifactPersister: fixture.store,
            xorComparator: comparator,
            now: { fixture.generatedAt }
        ).execute(fixture.request)

        #expect(result.status == .completed)
        #expect(result.payload.completed)
        #expect(result.payload.xorResult?.method == .geometricXOR)
        #expect(result.payload.xorResult?.differenceCount == 0)
        #expect(result.payload.xorResult?.differenceAreaSquareMicrometers == 0)
        #expect(result.payload.xorResult?.rawReportDigest == result.payload.xorResult?.evidenceArtifact?.digest)
        #expect(result.payload.handoff?.isSelfConsistent == true)
        #expect(result.payload.handoffArtifact?.locator == fixture.request.handoffOutput)
        #expect(Set(result.provenance.inputs).isSuperset(of: Set(fixture.request.inputs)))
        let xorQualification = try #require(result.payload.xorResult?.processQualification)
        let qualificationArtifacts = xorQualification.identityArtifacts.all
            + xorQualification.evidenceArtifacts
            + xorQualification.inputArtifacts
            + xorQualification.outputArtifacts
        #expect(Set(result.provenance.inputs).isSuperset(of: Set(qualificationArtifacts)))
        #expect(Set(try #require(result.payload.handoff).artifacts)
            .isSuperset(of: Set(qualificationArtifacts)))
    }

    @Test("canonical handoff rejects reordered and duplicated artifact inventories")
    func canonicalHandoffRejectsAmbiguousArtifactInventory() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        let comparator = try await fixture.qualifiedComparator()
        let result = try await DefaultTapeoutPackaging(
            artifactPersister: fixture.store,
            xorComparator: comparator,
            now: { fixture.generatedAt }
        ).execute(fixture.request)
        let retained = try #require(result.payload.handoff)

        var reordered = retained
        reordered.artifacts.reverse()
        #expect(throws: FoundryHandoffManifestError.self) {
            try FoundryHandoffManifest.decodeCanonical(from: reordered.canonicalData())
        }

        var duplicated = retained
        duplicated.artifacts.append(try #require(retained.artifacts.first))
        duplicated.manifestDigest = try duplicated.computedManifestDigest()
        #expect(duplicated.isSelfConsistent == false)
        #expect(throws: FoundryHandoffManifestError.self) {
            try FoundryHandoffManifest.decodeCanonical(from: duplicated.canonicalData())
        }

        let original = try #require(retained.artifacts.first)
        let producerless = ArtifactReference(
            id: original.id,
            locator: original.locator,
            digest: original.digest,
            byteCount: original.byteCount
        )
        var missingProducer = retained
        missingProducer.artifacts[0] = producerless
        missingProducer.manifestDigest = try missingProducer.computedManifestDigest()
        #expect(missingProducer.isSelfConsistent == false)
        #expect(throws: FoundryHandoffManifestError.self) {
            try FoundryHandoffManifest.decodeCanonical(from: missingProducer.canonicalData())
        }
    }

    @Test("geometric differences fail tapeout and retain typed XOR metrics")
    func geometricDifferenceFailsTapeout() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        let qualification = try await ProductionTrustFixture(
            root: fixture.root,
            evaluatedAt: fixture.generatedAt,
            toolID: "qualified-layout-xor"
        )
        let comparator = QualifiedGeometricXORExecutor(
            configuration: try fixture.geometricXORConfiguration(
                qualification: qualification.processQualification
            ),
            artifactPersister: fixture.store,
            processRunner: DifferenceReportingProcessRunner(),
            now: { fixture.generatedAt }
        )

        let result = try await DefaultTapeoutPackaging(
            artifactPersister: fixture.store,
            xorComparator: comparator,
            now: { fixture.generatedAt }
        ).execute(fixture.request)

        #expect(result.status == .failed)
        #expect(result.payload.xorResult?.executionStatus == .completed)
        #expect(result.payload.xorResult?.differenceCount == 2)
        #expect(result.payload.xorResult?.differenceAreaSquareMicrometers == 0.5)
        #expect(result.payload.handoff == nil)
    }

    @Test("expired geometric XOR qualification blocks execution before launch")
    func expiredQualificationBlocksTapeout() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        let qualification = try await ProductionTrustFixture(
            root: fixture.root,
            evaluatedAt: fixture.generatedAt,
            toolID: "qualified-layout-xor"
        )
        let comparator = QualifiedGeometricXORExecutor(
            configuration: try fixture.geometricXORConfiguration(
                qualification: qualification.processQualification
            ),
            artifactPersister: fixture.store,
            processRunner: UnexpectedProcessRunner(),
            now: { fixture.generatedAt.addingTimeInterval(100) }
        )

        let result = try await DefaultTapeoutPackaging(
            artifactPersister: fixture.store,
            xorComparator: comparator,
            now: { fixture.generatedAt }
        ).execute(fixture.request)

        #expect(result.status == .blocked)
        #expect(result.payload.xorResult?.executionStatus == .unqualified)
        #expect(result.payload.handoff == nil)
    }

    @Test("geometric XOR preserves timeout, cancellation, and nonzero exit states")
    func geometricXORProcessFailuresAreTyped() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        let qualification = try await ProductionTrustFixture(
            root: fixture.root,
            evaluatedAt: fixture.generatedAt,
            toolID: "qualified-layout-xor"
        )
        let configuration = try fixture.geometricXORConfiguration(
            qualification: qualification.processQualification
        )
        let source = fixture.request.physicalDesign.layoutArtifact

        let timeout = await QualifiedGeometricXORExecutor(
            configuration: configuration,
            artifactPersister: fixture.store,
            processRunner: TimeoutProcessRunner(),
            now: { fixture.generatedAt }
        ).compare(
            source: source,
            streamed: source,
            pdkDigest: fixture.request.pdk.digest,
            projectRoot: fixture.root
        )
        #expect(timeout.status == .blocked)
        #expect(timeout.executionStatus == .timedOut)

        let cancellation = await QualifiedGeometricXORExecutor(
            configuration: configuration,
            artifactPersister: fixture.store,
            processRunner: CancelledProcessRunner(),
            now: { fixture.generatedAt }
        ).compare(
            source: source,
            streamed: source,
            pdkDigest: fixture.request.pdk.digest,
            projectRoot: fixture.root
        )
        #expect(cancellation.status == .blocked)
        #expect(cancellation.executionStatus == .cancelled)

        let nonzeroExit = await QualifiedGeometricXORExecutor(
            configuration: configuration,
            artifactPersister: fixture.store,
            processRunner: NonzeroExitProcessRunner(),
            now: { fixture.generatedAt }
        ).compare(
            source: source,
            streamed: source,
            pdkDigest: fixture.request.pdk.digest,
            projectRoot: fixture.root
        )
        #expect(nonzeroExit.status == .failed)
        #expect(nonzeroExit.executionStatus == .exitedWithFailure)
        #expect(nonzeroExit.exitCode == 23)
    }

    @Test("missing project root blocks integrity verification")
    func missingIntegrityContext() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        let original = fixture.request
        let request = TapeoutRequest(
            runID: original.runID,
            inputs: original.inputs,
            signoffBundle: original.signoffBundle,
            authorization: original.authorization,
            physicalDesign: original.physicalDesign,
            pdk: original.pdk,
            streamOut: original.streamOut,
            foundryID: original.foundryID,
            handoffOutput: original.handoffOutput,
            evidence: original.evidence
        )

        let result = try await DefaultTapeoutPackaging(
            artifactPersister: fixture.store
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "HANDOFF_PROJECT_ROOT_REQUIRED" })
    }

    @Test("immutable artifact persistence serializes concurrent stream writers")
    func concurrentImmutableStreamTarget() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        let comparator = try await fixture.qualifiedComparator()
        let engine = DefaultTapeoutPackaging(
            artifactPersister: fixture.store,
            xorComparator: comparator,
            now: { fixture.generatedAt }
        )

        async let first = engine.execute(fixture.request)
        async let second = engine.execute(fixture.request)
        let results = try await [first, second]

        #expect(results.filter { $0.status == .completed }.count == 1)
        #expect(results.filter { $0.status == .blocked }.count == 1)
        #expect(results.contains { result in
            result.diagnostics.contains { $0.code.rawValue == "STREAM_OUT_PERSISTENCE_BLOCKED" }
        })
    }

    @Test("local persistence reports a typed immutable target conflict")
    func typedImmutableTargetConflict() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "release-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Failed to remove release store fixture: \(error.localizedDescription)")
            }
        }
        let store = LocalReleaseArtifactStore()
        let locator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: "release/immutable.json"),
            role: .output,
            kind: .release,
            format: .json
        )
        let request = ReleaseArtifactPersistenceRequest(
            locator: locator,
            bytes: Data("{}".utf8),
            producer: try ProducerIdentity(kind: .engine, identifier: "test.release", version: "1.0.0")
        )
        async let first = attemptPersistence(store: store, request: request, root: root)
        async let second = attemptPersistence(store: store, request: request, root: root)
        let outcomes = await [first, second]

        #expect(outcomes.filter { $0 == nil }.count == 1)
        #expect(outcomes.filter {
            $0 == .targetAlreadyExists("release/immutable.json")
        }.count == 1)
    }

    @Test("local persistence rejects a symbolic link escape with a typed error")
    func rejectsSymbolicLinkEscape() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "release-store-root-\(UUID().uuidString)", directoryHint: .isDirectory)
        let outside = FileManager.default.temporaryDirectory
            .appending(path: "release-store-outside-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            for directory in [root, outside] {
                do {
                    try FileManager.default.removeItem(at: directory)
                } catch {
                    Issue.record("Failed to remove release store fixture: \(error.localizedDescription)")
                }
            }
        }
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "escape"),
            withDestinationURL: outside
        )
        let request = ReleaseArtifactPersistenceRequest(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "escape/release.json"),
                role: .output,
                kind: .release,
                format: .json
            ),
            bytes: Data("{}".utf8),
            producer: try ProducerIdentity(kind: .engine, identifier: "test.release", version: "1.0.0")
        )

        let error = await attemptPersistence(
            store: LocalReleaseArtifactStore(),
            request: request,
            root: root
        )

        #expect(error == .invalidLocation("escape/release.json"))
        #expect(!FileManager.default.fileExists(atPath: outside.appending(path: "release.json").path))
    }

    @Test("tapeout rejects a persisted artifact with substituted producer provenance")
    func rejectsPersistedProducerSubstitution() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }

        let result = try await DefaultTapeoutPackaging(
            artifactPersister: ProducerSubstitutingArtifactStore(),
            now: { fixture.generatedAt }
        ).execute(fixture.request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "STREAM_OUT_PERSISTENCE_BLOCKED"
        })
    }

    @Test("tapeout rejects an absolute stream output outside the project")
    func rejectsAbsoluteStreamOutput() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        let original = fixture.request
        let generation = original.streamOut
        let outside = FileManager.default.temporaryDirectory
            .appending(path: "outside-\(UUID().uuidString).gds")
        let request = TapeoutRequest(
            runID: original.runID,
            inputs: original.inputs,
            signoffBundle: original.signoffBundle,
            authorization: original.authorization,
            physicalDesign: original.physicalDesign,
            pdk: original.pdk,
            streamOut: StreamOutGenerationRequest(
                output: ArtifactLocator(
                    location: try ArtifactLocation(fileURL: outside),
                    role: generation.output.role,
                    kind: generation.output.kind,
                    format: generation.output.format
                ),
                topCell: generation.topCell,
                unitsPerDatabaseUnit: generation.unitsPerDatabaseUnit,
                layerMap: generation.layerMap,
                hierarchyDepth: generation.hierarchyDepth,
                seal: generation.seal,
                padCells: generation.padCells,
                generatorID: generation.generatorID,
                generatorVersion: generation.generatorVersion,
                requirements: generation.requirements
            ),
            foundryID: original.foundryID,
            projectRoot: original.projectRoot,
            handoffOutput: original.handoffOutput,
            evidence: original.evidence
        )

        let result = try await DefaultTapeoutPackaging(
            artifactPersister: fixture.store
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "STREAM_OUT_TARGET_INVALID" })
        #expect(!FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("tapeout rejects a PDK digest that does not identify its manifest")
    func rejectsPDKManifestMismatch() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        var request = fixture.request
        request.pdk.digest = String(repeating: "f", count: 64)

        let result = try await DefaultTapeoutPackaging(
            artifactPersister: fixture.store
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "PDK_REFERENCE_INVALID" })
    }

    @Test("tapeout evidence inventory must match the canonical signoff bundle")
    func rejectsSignoffEvidenceInventoryMismatch() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        var request = fixture.request
        request.evidence = []

        let result = try await DefaultTapeoutPackaging(
            artifactPersister: fixture.store
        ).execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "SIGNOFF_BUNDLE_CONTENT_MISMATCH"
        })
    }
}

private func attemptPersistence(
    store: LocalReleaseArtifactStore,
    request: ReleaseArtifactPersistenceRequest,
    root: URL
) async -> LocalReleaseArtifactStoreError? {
    do {
        _ = try await store.persist(request, relativeTo: root)
        return nil
    } catch let error as LocalReleaseArtifactStoreError {
        return error
    } catch {
        Issue.record("Unexpected immutable persistence error: \(error.localizedDescription)")
        return .writeFailed(path: request.locator.location.value, stage: .contentWrite)
    }
}

private struct TapeoutFixture {
    let root: URL
    let generatedAt = Date(timeIntervalSince1970: 2_000)
    let store = TestReleaseArtifactStore()
    let request: TapeoutRequest

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "tapeout-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let designDigest = String(repeating: "1", count: 64)
        let physicalProducer = try ProducerIdentity(
            kind: .engine,
            identifier: "physical-design",
            version: "1.0.0"
        )
        let pdkProducer = try ProducerIdentity(
            kind: .library,
            identifier: "pdk-kit",
            version: "1.0.0"
        )
        let layout = try Self.write(
            Data([0, 6, 0, 2, 0, 4, 0, 0, 0, 0]),
            path: "layout/top.gds",
            kind: .layout,
            format: .gdsii,
            root: root,
            producer: physicalProducer
        )
        let pdkManifest = try Self.write(
            Data("pdk".utf8),
            path: "pdk/manifest.json",
            kind: .technology,
            format: .json,
            root: root,
            producer: pdkProducer
        )
        let pdkDigest = pdkManifest.digest.hexadecimalValue
        let report = try Self.write(
            Data("report".utf8),
            path: "reports/drc.json",
            kind: .report,
            format: .json,
            root: root,
            producer: try ProducerIdentity(
                kind: .tool,
                identifier: "signoff-tool",
                version: "1.0.0"
            )
        )
        let bundle = SignoffBundle(
            bundleID: "bundle",
            profileID: "digital",
            designDigest: designDigest,
            pdkDigest: pdkDigest,
            finalLayoutDigest: layout.digest.hexadecimalValue,
            axisResults: ReleaseSignoffAxis.allCases.map {
                SignoffAxisResult(axis: $0, disposition: .passed, evidenceIDs: ["e-\($0.rawValue)"], reason: "passed")
            },
            waivers: [],
            evidenceArtifacts: [report],
            toolQualificationScopes: [ToolQualificationScope(
                implementationID: "signoff-tool",
                toolVersion: "1.0.0",
                binaryDigest: String(repeating: "4", count: 64),
                algorithmVersion: "signoff-v1",
                processProfileID: "process",
                processProfileDigest: String(repeating: "5", count: 64),
                deckDigest: String(repeating: "6", count: 64),
                pdkID: "process",
                pdkDigest: pdkDigest,
                oracle: ToolOracleQualificationScope(
                    implementationID: "signoff-oracle",
                    version: "2.0.0",
                    binaryDigest: String(repeating: "7", count: 64)
                )
            )],
            evidenceDigest: String(repeating: "3", count: 64),
            issuedAt: generatedAt.addingTimeInterval(-1)
        )
        let bundleArtifact = try Self.write(
            try bundle.canonicalData(),
            path: "release/signoff.json",
            kind: .release,
            format: .json,
            root: root,
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "native.release.signoff",
                version: "2.0.0",
                build: String(repeating: "a", count: 64)
            )
        )
        let planArtifact = try Self.write(
            Data("approved release plan".utf8),
            path: "release/plan.json",
            kind: .request,
            format: .json,
            root: root,
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "design-flow-kernel",
                version: "1.0.0"
            )
        )
        let approval = FlowApprovalRecord(
            runID: "tapeout",
            stageID: "release.authorization",
            verdict: .approved,
            reviewer: "human-reviewer",
            reviewerKind: .human,
            createdAt: generatedAt.addingTimeInterval(-0.5),
            evidence: FlowApprovalEvidenceBinding(
                plan: planArtifact,
                stageResult: bundleArtifact
            )
        )
        let authorizationProducer = try ProducerIdentity(
            kind: .engine,
            identifier: "native.release.authorization",
            version: "2.0.0",
            build: String(repeating: "b", count: 64)
        )
        let authorization = ReleaseAuthorizationResult(
            status: .authorized,
            signoffBundle: SignoffBundleReference(
                artifact: bundleArtifact,
                designDigest: designDigest,
                pdkDigest: pdkDigest,
                finalLayoutDigest: layout.digest.hexadecimalValue
            ),
            approval: approval,
            diagnostics: [],
            provenance: try ExecutionProvenance(
                producer: authorizationProducer,
                inputs: [bundleArtifact, planArtifact, report],
                startedAt: generatedAt.addingTimeInterval(-0.5),
                completedAt: generatedAt.addingTimeInterval(-0.25)
            )
        )
        let authorizationEncoder = JSONEncoder()
        authorizationEncoder.dateEncodingStrategy = .iso8601
        authorizationEncoder.outputFormatting = [.sortedKeys]
        let authorizationArtifact = try Self.write(
            try authorizationEncoder.encode(authorization),
            path: "release/authorization.json",
            kind: .report,
            format: .json,
            root: root,
            producer: authorizationProducer
        )
        let physical = PhysicalDesignReference(
            layoutArtifact: layout,
            topCell: "TOP",
            layoutDigest: layout.digest.hexadecimalValue
        )
        let pdk = PDKReference(manifest: pdkManifest, processID: "process", version: "1", digest: pdkDigest)
        let requirements = TapeoutReleaseRequirements(
            expectedTopCell: "TOP",
            expectedUnitsPerDatabaseUnit: 0.001,
            requiredLayerIDs: ["M1"],
            requiredPadCells: ["PAD"],
            requiredSeal: "seal"
        )
        let streamOut = StreamOutGenerationRequest(
            output: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "release/top.gds"),
                role: .output,
                kind: .layout,
                format: .gdsii
            ),
            topCell: "TOP",
            unitsPerDatabaseUnit: 0.001,
            layerMap: ["M1": 1],
            hierarchyDepth: 1,
            seal: "seal",
            padCells: ["PAD"],
            generatorID: "native.release.stream-out",
            generatorVersion: "1.0.0",
            requirements: requirements
        )
        request = TapeoutRequest(
            runID: "tapeout",
            inputs: [authorizationArtifact, bundleArtifact, pdkManifest, layout, report],
            signoffBundle: SignoffBundleReference(
                artifact: bundleArtifact,
                designDigest: designDigest,
                pdkDigest: pdkDigest,
                finalLayoutDigest: layout.digest.hexadecimalValue
            ),
            authorization: authorizationArtifact,
            physicalDesign: physical,
            pdk: pdk,
            streamOut: streamOut,
            foundryID: "foundry",
            projectRoot: root.path,
            handoffOutput: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "release/handoff.json"),
                role: .output,
                kind: .release,
                format: .json
            ),
            evidence: [report]
        )
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove tapeout fixture: \(error.localizedDescription)")
        }
    }

    func qualifiedComparator() async throws -> QualifiedGeometricXORExecutor {
        let qualification = try await ProductionTrustFixture(
            root: root,
            evaluatedAt: generatedAt,
            toolID: "qualified-layout-xor"
        )
        return QualifiedGeometricXORExecutor(
            configuration: try geometricXORConfiguration(
                qualification: qualification.processQualification
            ),
            artifactPersister: store,
            now: { generatedAt }
        )
    }

    func geometricXORConfiguration(
        qualification: ToolProcessQualificationEvidence
    ) throws -> GeometricXORToolConfiguration {
        try GeometricXORToolConfiguration(
            qualification: qualification,
            reportOutput: ArtifactLocator(
                location: try ArtifactLocation(
                    workspaceRelativePath: "release/layout-xor-report.json"
                ),
                role: .output,
                kind: .report,
                format: .json
            )
        )
    }

    private static func write(
        _ data: Data,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        root: URL,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: kind,
                format: format
            ),
            relativeTo: root,
            producer: producer
        )
    }
}

private struct DifferenceReportingProcessRunner: TimedProcessRunning {
    func run(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async throws -> TimedProcessResult {
        if try await cancellationCheck?() == true {
            throw TimedProcessError.cancelled(
                executablePath: process.executableURL?.path ?? "unknown",
                standardOutput: "",
                standardError: ""
            )
        }
        let arguments = process.arguments ?? []
        guard let reportIndex = arguments.firstIndex(of: "--report"),
              arguments.indices.contains(reportIndex + 1) else {
            throw TimedProcessError.invalidConfiguration("--report is required")
        }
        let report = try LayoutXORReport(
            differenceCount: 2,
            differenceAreaSquareMicrometers: 0.5
        )
        try report.canonicalData().write(
            to: URL(fileURLWithPath: arguments[reportIndex + 1]),
            options: .atomic
        )
        return TimedProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

private struct UnexpectedProcessRunner: TimedProcessRunning {
    func run(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async throws -> TimedProcessResult {
        Issue.record("An unqualified geometric XOR process must not launch.")
        return TimedProcessResult(exitCode: 0, standardOutput: "", standardError: "")
    }
}

private struct TimeoutProcessRunner: TimedProcessRunning {
    func run(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async throws -> TimedProcessResult {
        throw TimedProcessError.timedOut(
            executablePath: process.executableURL?.path ?? "unknown",
            timeoutSeconds: 1,
            standardOutput: "",
            standardError: ""
        )
    }
}

private struct CancelledProcessRunner: TimedProcessRunning {
    func run(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async throws -> TimedProcessResult {
        throw TimedProcessError.cancelled(
            executablePath: process.executableURL?.path ?? "unknown",
            standardOutput: "",
            standardError: ""
        )
    }
}

private struct NonzeroExitProcessRunner: TimedProcessRunning {
    func run(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async throws -> TimedProcessResult {
        TimedProcessResult(exitCode: 23, standardOutput: "", standardError: "")
    }
}

private actor TestReleaseArtifactStore: ReleaseArtifactPersisting {
    func persist(
        _ request: ReleaseArtifactPersistenceRequest,
        relativeTo projectRoot: URL
    ) async throws -> ArtifactReference {
        let url = try request.locator.location.resolvedFileURL(relativeTo: projectRoot)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw TapeoutArtifactGenerationError.persistenceFailed("the immutable target already exists")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try request.bytes.write(to: url, options: .withoutOverwriting)
        return try LocalArtifactReferencer().reference(
            request.locator,
            relativeTo: projectRoot,
            producer: request.producer
        )
    }

    func load(
        _ artifact: ArtifactReference,
        relativeTo projectRoot: URL
    ) async throws -> Data {
        let url = try artifact.locator.location.resolvedFileURL(relativeTo: projectRoot)
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

private actor ProducerSubstitutingArtifactStore: ReleaseArtifactPersisting {
    private let store = TestReleaseArtifactStore()

    func persist(
        _ request: ReleaseArtifactPersistenceRequest,
        relativeTo projectRoot: URL
    ) async throws -> ArtifactReference {
        let artifact = try await store.persist(request, relativeTo: projectRoot)
        return ArtifactReference(
            id: artifact.id,
            locator: artifact.locator,
            digest: artifact.digest,
            byteCount: artifact.byteCount,
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "substituted.release.producer",
                version: "1.0.0"
            )
        )
    }

    func load(
        _ artifact: ArtifactReference,
        relativeTo projectRoot: URL
    ) async throws -> Data {
        try await store.load(artifact, relativeTo: projectRoot)
    }
}
