import Foundation
import PDKCore
import PhysicalDesignCore
import ReleaseCore
import CircuiteFoundation

public struct DefaultTapeoutPackaging: TapeoutPackaging {
    private let streamEncoder: any LayoutStreamEncoding
    private let artifactPersister: any ReleaseArtifactPersisting
    private let streamOutValidator: any StreamOutValidating
    private let xorComparator: any LayoutXORComparing
    private let verifier: LocalArtifactVerifier
    private let now: @Sendable () -> Date

    public init(
        artifactPersister: any ReleaseArtifactPersisting = LocalReleaseArtifactStore(),
        streamEncoder: any LayoutStreamEncoding = ExactLayoutStreamEncoder(),
        streamOutValidator: any StreamOutValidating = DefaultStreamOutValidator(),
        xorComparator: any LayoutXORComparing = DefaultLayoutXORComparator(),
        verifier: LocalArtifactVerifier = LocalArtifactVerifier(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.artifactPersister = artifactPersister
        self.streamEncoder = streamEncoder
        self.streamOutValidator = streamOutValidator
        self.xorComparator = xorComparator
        self.verifier = verifier
        self.now = now
    }

    public func execute(_ request: TapeoutRequest) async throws -> TapeoutResult {
        let startedAt = now()
        let producer = try ProducerIdentity(
            kind: .engine,
            identifier: "native.release.tapeout",
            version: "2.0.0",
            build: ReleaseRuntimeIdentity.currentExecutableDigest()
        )
        var diagnostics: [DesignDiagnostic] = []
        var status: ReleaseExecutionStatus = .completed
        var streamedArtifact: ArtifactReference?
        var streamOutManifest: StreamOutManifest?
        var xorResult: LayoutXORResult?
        var handoff: FoundryHandoffManifest?
        var handoffArtifact: ArtifactReference?

        func add(_ code: String, _ message: String, entity: String?, blocked: Bool) {
            diagnostics.append(DesignDiagnostic(
                severity: .error,
                code: code,
                message: message,
                entity: entity,
                suggestedActions: ["inspect_tapeout_request", "rerun_release_signoff_or_stream_out"]
            ))
            if blocked {
                status = .blocked
            } else if status != .blocked {
                status = .failed
            }
        }

        guard request.schemaVersion == TapeoutRequest.currentSchemaVersion else {
            add("INVALID_TAPEOUT_SCHEMA", "Unsupported tapeout request schema version.", entity: request.runID, blocked: true)
            return try envelope(request: request, status: status, diagnostics: diagnostics, startedAt: startedAt, producer: producer, payload: emptyPayload(request))
        }
        guard !request.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            add("RUN_ID_REQUIRED", "Tapeout run ID must not be empty.", entity: nil, blocked: true)
            return try envelope(request: request, status: status, diagnostics: diagnostics, startedAt: startedAt, producer: producer, payload: emptyPayload(request))
        }
        guard !request.foundryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            add("FOUNDRY_ID_REQUIRED", "Foundry ID is required for handoff.", entity: request.runID, blocked: true)
            return try envelope(request: request, status: status, diagnostics: diagnostics, startedAt: startedAt, producer: producer, payload: emptyPayload(request))
        }
        guard let projectRootPath = request.projectRoot else {
            add("HANDOFF_PROJECT_ROOT_REQUIRED", "A project root is required to generate and verify tapeout artifacts.", entity: request.runID, blocked: true)
            return try envelope(request: request, status: status, diagnostics: diagnostics, startedAt: startedAt, producer: producer, payload: emptyPayload(request))
        }
        let projectRoot = URL(fileURLWithPath: projectRootPath)

        validateReleaseBindings(request, add: add)
        verifyRetainedArtifacts(
            request,
            projectRoot: projectRoot,
            evaluatedAt: startedAt,
            add: add
        )
        guard status == .completed else {
            return try envelope(
                request: request,
                status: status,
                diagnostics: diagnostics,
                artifacts: uniqueArtifacts([
                    request.authorization,
                    request.signoffBundle.artifact,
                    request.pdk.manifest,
                    request.physicalDesign.layoutArtifact,
                ] + request.evidence),
                startedAt: startedAt,
                producer: producer,
                payload: emptyPayload(request)
            )
        }
        do {
            let generation = request.streamOut
            try validateStreamOutGeneration(generation, source: request.physicalDesign)
            try validateHandoffTarget(request.handoffOutput)
            let bytes = try await streamEncoder.encode(
                request.physicalDesign,
                format: generation.output.format,
                relativeTo: projectRoot
            )
            guard hasValidLayoutSignature(bytes, format: generation.output.format) else {
                throw TapeoutArtifactGenerationError.invalidStreamOutRequest(
                    "generated bytes do not contain the declared standard-stream signature"
                )
            }
            let streamProducer = try ProducerIdentity(
                kind: .engine,
                identifier: generation.generatorID,
                version: generation.generatorVersion,
                build: ReleaseRuntimeIdentity.currentExecutableDigest()
            )
            let artifact = try await persist(
                locator: generation.output,
                bytes: bytes,
                producer: streamProducer,
                projectRoot: projectRoot
            )
            try await verifyPersistedArtifact(
                artifact,
                expectedLocator: generation.output,
                expectedBytes: bytes,
                expectedProducer: streamProducer,
                projectRoot: projectRoot
            )
            streamedArtifact = artifact
            let manifest = StreamOutManifest(
                streamedArtifact: artifact,
                topCell: generation.topCell,
                unitsPerDatabaseUnit: generation.unitsPerDatabaseUnit,
                layerMap: generation.layerMap,
                hierarchyDepth: generation.hierarchyDepth,
                seal: generation.seal,
                padCells: generation.padCells,
                generatedBy: "\(generation.generatorID)@\(generation.generatorVersion)"
            )
            streamOutManifest = manifest
            let validation = streamOutValidator.validate(StreamOutRequest(
                sourceLayout: request.physicalDesign,
                manifest: manifest,
                projectRoot: projectRoot.path,
                requirements: generation.requirements
            ))
            diagnostics.append(contentsOf: validation.diagnostics)
            switch validation.status {
            case .blocked:
                status = .blocked
            case .failed where status != .blocked:
                status = .failed
            case .passed, .failed:
                break
            }
        } catch let error as LayoutStreamEncodingError {
            add("STREAM_OUT_ENCODING_BLOCKED", error.localizedDescription, entity: request.runID, blocked: true)
        } catch let error as TapeoutArtifactGenerationError {
            switch error {
            case .invalidStreamOutRequest:
                add("STREAM_OUT_REQUEST_INVALID", error.localizedDescription, entity: request.runID, blocked: true)
            case .invalidPersistenceTarget:
                add("STREAM_OUT_TARGET_INVALID", error.localizedDescription, entity: request.runID, blocked: true)
            case .persistenceFailed, .persistedArtifactMismatch, .persistedArtifactUnreadable:
                add("STREAM_OUT_PERSISTENCE_BLOCKED", error.localizedDescription, entity: request.runID, blocked: true)
            }
        } catch {
            add("STREAM_OUT_GENERATION_FAILED", error.localizedDescription, entity: request.runID, blocked: true)
        }

        if let streamedArtifact {
            xorResult = await xorComparator.compare(
                source: request.physicalDesign.layoutArtifact,
                streamed: streamedArtifact,
                pdkDigest: request.pdk.digest,
                projectRoot: projectRoot
            )
            if xorResult?.status == .blocked {
                add("LAYOUT_XOR_BLOCKED", xorResult?.message ?? "Layout XOR comparison is blocked.", entity: request.runID, blocked: true)
            } else if xorResult?.status == .failed {
                add("LAYOUT_XOR_FAILED", xorResult?.message ?? "Layout comparison failed.", entity: request.runID, blocked: false)
            } else if xorResult?.isTapeoutQualified(at: startedAt) != true {
                add(
                    "LAYOUT_XOR_QUALIFICATION_REQUIRED",
                    "Tapeout requires immutable evidence from a production-qualified geometric XOR implementation. Byte identity is diagnostic evidence only.",
                    entity: request.runID,
                    blocked: true
                )
            } else if xorResult?.processQualification?.scope.pdkDigest?
                .caseInsensitiveCompare(request.pdk.digest) != .orderedSame {
                add(
                    "LAYOUT_XOR_PDK_SCOPE_MISMATCH",
                    "The qualified geometric XOR scope does not match the tapeout PDK digest.",
                    entity: request.runID,
                    blocked: true
                )
            }
        }

        verifyXORArtifacts(xorResult, projectRoot: projectRoot, add: add)

        if status == .completed, let streamedArtifact, let xorResult {
            let generatedAt = now()
            let xorArtifacts = retainedXORArtifacts(xorResult)
            let evidenceIDs = Array(Set(
                request.evidence.map(\.artifactID)
                    + xorArtifacts.map(\.artifactID)
            )).sorted()
            let artifacts = uniqueArtifacts([
                request.authorization,
                request.signoffBundle.artifact,
                request.pdk.manifest,
                request.physicalDesign.layoutArtifact,
                streamedArtifact,
            ] + request.evidence + xorArtifacts)
            let unsigned = FoundryHandoffManifest(
                releaseID: "\(request.runID)-tapeout",
                foundryID: request.foundryID,
                signoffBundleArtifactDigest: request.signoffBundle.artifact.digest.hexadecimalValue,
                designDigest: request.signoffBundle.designDigest,
                pdkDigest: request.pdk.digest,
                layoutDigest: request.physicalDesign.layoutDigest,
                artifacts: artifacts,
                evidenceIDs: evidenceIDs,
                layoutXORResult: xorResult,
                generatedAt: generatedAt,
                manifestDigest: ""
            )
            let generatedHandoff = FoundryHandoffManifest(
                releaseID: unsigned.releaseID,
                foundryID: unsigned.foundryID,
                signoffBundleArtifactDigest: unsigned.signoffBundleArtifactDigest,
                designDigest: unsigned.designDigest,
                pdkDigest: unsigned.pdkDigest,
                layoutDigest: unsigned.layoutDigest,
                artifacts: unsigned.artifacts,
                evidenceIDs: unsigned.evidenceIDs,
                layoutXORResult: unsigned.layoutXORResult,
                generatedAt: unsigned.generatedAt,
                manifestDigest: try unsigned.computedManifestDigest()
            )
            do {
                let bytes = try generatedHandoff.canonicalData()
                let artifact = try await persist(
                    locator: request.handoffOutput,
                    bytes: bytes,
                    producer: producer,
                    projectRoot: projectRoot
                )
                try await verifyPersistedArtifact(
                    artifact,
                    expectedLocator: request.handoffOutput,
                    expectedBytes: bytes,
                    expectedProducer: producer,
                    projectRoot: projectRoot
                )
                let persistedBytes = try await artifactPersister.load(artifact, relativeTo: projectRoot)
                let persisted = try FoundryHandoffManifest.decodeCanonical(from: persistedBytes)
                guard persisted == generatedHandoff, persisted.isSelfConsistent else {
                    throw TapeoutArtifactGenerationError.persistedArtifactMismatch(
                        "decoded handoff content does not equal the generated manifest"
                    )
                }
                handoff = persisted
                handoffArtifact = artifact
            } catch let error as TapeoutArtifactGenerationError {
                add("TAPEOUT_HANDOFF_PERSISTENCE_BLOCKED", error.localizedDescription, entity: request.runID, blocked: true)
            } catch {
                add("TAPEOUT_HANDOFF_GENERATION_FAILED", error.localizedDescription, entity: request.runID, blocked: true)
            }
        }

        let completed = status == .completed && handoff != nil && handoffArtifact != nil
        let payload = TapeoutPayload(
            handoffArtifact: completed ? handoffArtifact : nil,
            checksum: completed ? handoff?.manifestDigest : nil,
            completed: completed,
            layoutDigest: request.physicalDesign.layoutDigest,
            pdkDigest: request.pdk.digest,
            streamOut: streamOutManifest,
            xorResult: xorResult,
            handoff: handoff
        )
        return try envelope(
            request: request,
            status: completed ? .completed : status,
            diagnostics: diagnostics,
            artifacts: uniqueArtifacts([
                request.authorization,
                request.signoffBundle.artifact,
                request.pdk.manifest,
                request.physicalDesign.layoutArtifact,
            ] + request.evidence
                + (xorResult.map(retainedXORArtifacts) ?? [])
                + [streamedArtifact, handoffArtifact].compactMap { $0 }),
            additionalInputs: xorResult.map(retainedXORArtifacts) ?? [],
            startedAt: startedAt,
            producer: producer,
            payload: payload
        )
    }

    private func validateReleaseBindings(
        _ request: TapeoutRequest,
        add: (String, String, String?, Bool) -> Void
    ) {
        let bundle = request.signoffBundle
        let requiredInputs = Set([
            request.authorization,
            bundle.artifact,
            request.pdk.manifest,
            request.physicalDesign.layoutArtifact,
        ] + request.evidence)
        let declaredInputs = Set(request.inputs)
        for missing in requiredInputs.subtracting(declaredInputs).sorted(by: { $0.path < $1.path }) {
            add(
                "TAPEOUT_INPUT_BINDING_MISSING",
                "Tapeout inputs must include every signoff, PDK, layout, and evidence artifact used by the request.",
                missing.path,
                true
            )
        }
        if bundle.artifact.kind != .release {
            add("SIGNOFF_BUNDLE_KIND_INVALID", "Tapeout accepts only a release-kind signoff bundle artifact.", bundle.artifact.path, true)
        }
        if request.authorization.kind != .report
            || request.authorization.format != .json
            || request.authorization.producer?.kind != .engine
            || request.authorization.producer?.identifier != "native.release.authorization"
            || request.authorization.producer?.version != "2.0.0"
            || !isSHA256(request.authorization.producer?.build ?? "") {
            add(
                "RELEASE_AUTHORIZATION_ARTIFACT_INVALID",
                "Tapeout requires the canonical producer-bound release authorization result artifact.",
                request.authorization.path,
                true
            )
        }
        if bundle.artifact.producer?.kind != .engine
            || bundle.artifact.producer?.identifier != "native.release.signoff"
            || bundle.artifact.producer?.version != "2.0.0"
            || !isSHA256(bundle.artifact.producer?.build ?? "") {
            add(
                "SIGNOFF_BUNDLE_PRODUCER_INVALID",
                "Tapeout requires a bundle produced by the canonical signoff engine and exact version.",
                bundle.artifact.path,
                true
            )
        }
        if !isSHA256(bundle.designDigest) || !isSHA256(bundle.pdkDigest) {
            add("SIGNOFF_BUNDLE_DIGEST_REQUIRED", "Signoff bundle design and PDK digests must be SHA-256 values.", bundle.artifact.path, true)
        }
        if bundle.pdkDigest != request.pdk.digest {
            add("SIGNOFF_PDK_BINDING_MISMATCH", "Signoff bundle is bound to a different PDK revision.", bundle.artifact.path, false)
        }
        if bundle.finalLayoutDigest != request.physicalDesign.layoutDigest {
            add("SIGNOFF_LAYOUT_BINDING_MISMATCH", "Signoff bundle is not bound to the exact final layout revision.", bundle.artifact.path, false)
        }
        if bundle.artifact.byteCount == 0 || bundle.artifact.path.isEmpty {
            add("SIGNOFF_BUNDLE_ARTIFACT_INCOMPLETE", "Signoff bundle artifact reference must include path, SHA-256, and byte count.", bundle.artifact.path, true)
        }
        if request.pdk.manifest.kind != .technology {
            add("PDK_MANIFEST_KIND_INVALID", "PDK reference must point to a technology manifest artifact.", request.pdk.manifest.path, true)
        }
        do {
            try request.pdk.validate()
        } catch {
            add(
                "PDK_REFERENCE_INVALID",
                "The PDK reference does not bind its exact immutable manifest: \(error.localizedDescription)",
                request.pdk.manifest.path,
                true
            )
        }
        if request.physicalDesign.topCell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || request.physicalDesign.layoutArtifact.kind != .layout
            || request.physicalDesign.layoutArtifact.digest.algorithm != .sha256
            || request.physicalDesign.layoutDigest.caseInsensitiveCompare(
                request.physicalDesign.layoutArtifact.digest.hexadecimalValue
            ) != .orderedSame {
            add(
                "PHYSICAL_DESIGN_REFERENCE_INVALID",
                "The physical design must bind a non-empty top cell and the exact immutable layout artifact digest.",
                request.physicalDesign.layoutArtifact.path,
                true
            )
        }
        let handoffInputs = [
            request.authorization,
            bundle.artifact,
            request.pdk.manifest,
            request.physicalDesign.layoutArtifact,
        ] + request.evidence
        for artifact in handoffInputs where artifact.producer == nil {
            add(
                "HANDOFF_ARTIFACT_PRODUCER_REQUIRED",
                "Every artifact entering the foundry handoff must retain its exact producer identity.",
                artifact.path,
                true
            )
        }
    }

    private func validateStreamOutGeneration(
        _ generation: StreamOutGenerationRequest,
        source: PhysicalDesignReference
    ) throws {
        guard generation.schemaVersion == StreamOutGenerationRequest.currentSchemaVersion else {
            throw TapeoutArtifactGenerationError.invalidStreamOutRequest("unsupported schema version")
        }
        guard source.layoutArtifact.digest.algorithm == .sha256,
              source.layoutDigest.caseInsensitiveCompare(
                source.layoutArtifact.digest.hexadecimalValue
              ) == .orderedSame else {
            throw TapeoutArtifactGenerationError.invalidStreamOutRequest(
                "source layout identity does not match its immutable artifact digest"
            )
        }
        guard generation.output.location.storage == .workspaceRelative,
              generation.output.role == .output,
              generation.output.kind == .layout,
              generation.output.format == .gdsii || generation.output.format == .oasis else {
            throw TapeoutArtifactGenerationError.invalidPersistenceTarget(
                "stream-out must target an output layout in GDSII or OASIS format"
            )
        }
        guard generation.topCell == source.topCell,
              !generation.generatorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !generation.generatorVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TapeoutArtifactGenerationError.invalidStreamOutRequest(
                "top cell and generator identity must bind the source design"
            )
        }
        let requirements = generation.requirements
        guard generation.topCell == requirements.expectedTopCell,
              generation.unitsPerDatabaseUnit.isFinite,
              generation.unitsPerDatabaseUnit > 0,
              generation.unitsPerDatabaseUnit == requirements.expectedUnitsPerDatabaseUnit,
              generation.hierarchyDepth > 0,
              !generation.layerMap.isEmpty,
              Set(generation.layerMap.values).count == generation.layerMap.count,
              requirements.requiredLayerIDs.allSatisfy({ generation.layerMap[$0] != nil }),
              requirements.requiredPadCells.allSatisfy({ generation.padCells.contains($0) }),
              generation.seal == requirements.requiredSeal else {
            throw TapeoutArtifactGenerationError.invalidStreamOutRequest(
                "top cell, units, hierarchy, layer map, pad cells, and seal must satisfy the release requirements"
            )
        }
    }

    private func validateHandoffTarget(_ locator: ArtifactLocator) throws {
        guard locator.location.storage == .workspaceRelative,
              locator.role == .output,
              locator.kind == .release,
              locator.format == .json else {
            throw TapeoutArtifactGenerationError.invalidPersistenceTarget(
                "foundry handoff must target an output release artifact in JSON format"
            )
        }
    }

    private func verifyPersistedArtifact(
        _ artifact: ArtifactReference,
        expectedLocator: ArtifactLocator,
        expectedBytes: Data,
        expectedProducer: ProducerIdentity,
        projectRoot: URL
    ) async throws {
        guard artifact.locator == expectedLocator,
              artifact.producer == expectedProducer else {
            throw TapeoutArtifactGenerationError.persistedArtifactMismatch(
                "returned locator or producer differs from the persistence request"
            )
        }
        let expectedDigest = try SHA256ContentDigester().digest(data: expectedBytes)
        guard artifact.digest == expectedDigest,
              artifact.byteCount == UInt64(expectedBytes.count) else {
            throw TapeoutArtifactGenerationError.persistedArtifactMismatch("digest or byte count differs from generated bytes")
        }
        let loaded: Data
        do {
            loaded = try await artifactPersister.load(artifact, relativeTo: projectRoot)
        } catch {
            throw TapeoutArtifactGenerationError.persistedArtifactUnreadable(error.localizedDescription)
        }
        guard loaded == expectedBytes else {
            throw TapeoutArtifactGenerationError.persistedArtifactMismatch("reloaded bytes differ from generated bytes")
        }
    }

    private func persist(
        locator: ArtifactLocator,
        bytes: Data,
        producer: ProducerIdentity,
        projectRoot: URL
    ) async throws -> ArtifactReference {
        do {
            return try await artifactPersister.persist(
                ReleaseArtifactPersistenceRequest(
                    locator: locator,
                    bytes: bytes,
                    producer: producer
                ),
                relativeTo: projectRoot
            )
        } catch {
            throw TapeoutArtifactGenerationError.persistenceFailed(error.localizedDescription)
        }
    }

    private func verifyRetainedArtifacts(
        _ request: TapeoutRequest,
        projectRoot: URL,
        evaluatedAt: Date,
        add: (String, String, String?, Bool) -> Void
    ) {
        let bundle = request.signoffBundle
        let authorizationIntegrity = verifier.verify(request.authorization, relativeTo: projectRoot)
        if !authorizationIntegrity.isVerified {
            add(
                "RELEASE_AUTHORIZATION_INTEGRITY_FAILED",
                integrityMessage(authorizationIntegrity),
                request.authorization.path,
                true
            )
        } else {
            do {
                let authorizationURL = try request.authorization.locator.location
                    .resolvedFileURL(relativeTo: projectRoot)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let authorization = try decoder.decode(
                    ReleaseAuthorizationResult.self,
                    from: Data(contentsOf: authorizationURL, options: .mappedIfSafe)
                )
                guard authorization.schemaVersion
                        == ReleaseAuthorizationResult.currentSchemaVersion,
                      authorization.status == .authorized,
                      authorization.signoffBundle == request.signoffBundle,
                      authorization.approval.runID == request.runID,
                      authorization.approval.stageID == "release.authorization",
                      authorization.approval.verdict == .approved,
                      authorization.approval.reviewerKind == .human,
                      authorization.approval.evidence.stageResult == request.signoffBundle.artifact,
                      authorization.evidence.provenance.producer
                        == request.authorization.producer,
                      authorization.evidence.provenance.inputs.contains(
                        authorization.approval.evidence.plan
                      ),
                      authorization.evidence.provenance.inputs.contains(
                        request.signoffBundle.artifact
                      ) else {
                    add(
                        "RELEASE_AUTHORIZATION_CONTENT_INVALID",
                        "The retained authorization must approve this exact signoff bundle through a human-bound, provenance-complete decision.",
                        request.authorization.path,
                        true
                    )
                    return
                }
                let planIntegrity = verifier.verify(
                    authorization.approval.evidence.plan,
                    relativeTo: projectRoot
                )
                if !planIntegrity.isVerified {
                    add(
                        "RELEASE_AUTHORIZATION_APPROVAL_INTEGRITY_FAILED",
                        integrityMessage(planIntegrity),
                        authorization.approval.evidence.plan.path,
                        true
                    )
                }
            } catch {
                add(
                    "RELEASE_AUTHORIZATION_DECODE_FAILED",
                    "The retained release authorization result is invalid: \(error.localizedDescription)",
                    request.authorization.path,
                    true
                )
            }
        }
        let bundleIntegrity = verifier.verify(bundle.artifact, relativeTo: projectRoot)
        if !bundleIntegrity.isVerified {
            add("SIGNOFF_BUNDLE_INTEGRITY_FAILED", integrityMessage(bundleIntegrity), bundle.artifact.path, true)
        } else {
            do {
                let bundleURL = try bundle.artifact.locator.location.resolvedFileURL(relativeTo: projectRoot)
                let persistedBundle = try SignoffBundle.decodeCanonical(from: Data(contentsOf: bundleURL, options: .mappedIfSafe))
                if persistedBundle.designDigest != bundle.designDigest
                    || persistedBundle.pdkDigest != bundle.pdkDigest
                    || persistedBundle.finalLayoutDigest != bundle.finalLayoutDigest
                    || Set(persistedBundle.evidenceArtifacts) != Set(request.evidence) {
                    add("SIGNOFF_BUNDLE_CONTENT_MISMATCH", "The persisted signoff bundle does not match its release bindings.", bundle.artifact.path, true)
                }
                let axes = persistedBundle.axisResults.map(\.axis)
                if axes.count != ReleaseSignoffAxis.allCases.count
                    || Set(axes) != Set(ReleaseSignoffAxis.allCases)
                    || !persistedBundle.axisResults.allSatisfy({ $0.disposition.isReleaseEligible }) {
                    add(
                        "SIGNOFF_BUNDLE_AXIS_COVERAGE_INVALID",
                        "The persisted signoff bundle must contain exactly one release-eligible result for every release axis.",
                        bundle.artifact.path,
                        true
                    )
                }
                if persistedBundle.issuedAt > evaluatedAt {
                    add(
                        "SIGNOFF_BUNDLE_TIMESTAMP_INVALID",
                        "The signoff bundle was issued after the tapeout evaluation started.",
                        bundle.artifact.path,
                        true
                    )
                }
                if !persistedBundle.waiversAreValid(at: evaluatedAt) {
                    add(
                        "SIGNOFF_BUNDLE_WAIVER_INVALID",
                        "A signoff waiver is expired, unbound, duplicated, or does not match its waived axis evidence.",
                        bundle.artifact.path,
                        true
                    )
                }
            } catch {
                add("SIGNOFF_BUNDLE_DECODE_FAILED", "The persisted signoff bundle is not canonical: \(error.localizedDescription)", bundle.artifact.path, true)
            }
        }
        let retainedArtifacts = [
            request.authorization,
            request.pdk.manifest,
            request.physicalDesign.layoutArtifact,
        ] + request.inputs + request.evidence
        for artifact in Set(retainedArtifacts) {
            let integrity = verifier.verify(artifact, relativeTo: projectRoot)
            if !integrity.isVerified {
                add("HANDOFF_EVIDENCE_INTEGRITY_FAILED", integrityMessage(integrity), artifact.path, true)
            }
        }
    }

    private func verifyXORArtifacts(
        _ xorResult: LayoutXORResult?,
        projectRoot: URL,
        add: (String, String, String?, Bool) -> Void
    ) {
        let retainedArtifacts = xorResult.map(retainedXORArtifacts) ?? []
        for artifact in Set(retainedArtifacts) {
            if artifact.producer == nil {
                add(
                    "LAYOUT_XOR_QUALIFICATION_PRODUCER_REQUIRED",
                    "Every retained geometric XOR qualification artifact must identify its producer.",
                    artifact.path,
                    true
                )
                continue
            }
            let integrity = verifier.verify(artifact, relativeTo: projectRoot)
            if !integrity.isVerified {
                add("LAYOUT_XOR_QUALIFICATION_INTEGRITY_FAILED", integrityMessage(integrity), artifact.path, true)
            }
        }
    }

    private func retainedXORArtifacts(_ result: LayoutXORResult) -> [ArtifactReference] {
        let qualificationArtifacts = result.processQualification.map {
            $0.identityArtifacts.all
                + $0.evidenceArtifacts
                + $0.inputArtifacts
                + $0.outputArtifacts
        } ?? []
        return uniqueArtifacts([result.evidenceArtifact].compactMap { $0 } + qualificationArtifacts)
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
        }
    }

    private func hasValidLayoutSignature(_ data: Data, format: ArtifactFormat) -> Bool {
        switch format {
        case .oasis:
            data.starts(with: Data("%SEMI-OASIS".utf8))
        case .gdsii:
            data.count >= 4
                && data[data.startIndex] == 0
                && data[data.startIndex + 1] == 6
                && data[data.startIndex + 2] == 0
                && data[data.startIndex + 3] == 2
        default:
            false
        }
    }

    private func integrityMessage(_ integrity: ArtifactIntegrity) -> String {
        integrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; ")
    }

    private func uniqueArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        Array(Set(artifacts)).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func emptyPayload(_ request: TapeoutRequest) -> TapeoutPayload {
        TapeoutPayload(
            handoffArtifact: nil,
            checksum: nil,
            completed: false,
            layoutDigest: request.physicalDesign.layoutDigest,
            pdkDigest: request.pdk.digest
        )
    }

    private func envelope(
        request: TapeoutRequest,
        status: ReleaseExecutionStatus,
        diagnostics: [DesignDiagnostic],
        artifacts: [ArtifactReference] = [],
        additionalInputs: [ArtifactReference] = [],
        startedAt: Date,
        producer: ProducerIdentity,
        payload: TapeoutPayload
    ) throws -> TapeoutResult {
        let metadata = try ExecutionProvenance(
            producer: producer,
            inputs: uniqueArtifacts([
                request.authorization,
                request.signoffBundle.artifact,
                request.pdk.manifest,
                request.physicalDesign.layoutArtifact,
            ] + request.inputs + request.evidence + additionalInputs),
            invocation: ExecutionInvocation.inProcess(
                entryPoint: "TapeoutEngine.DefaultTapeoutPackaging.execute"
            ),
            environment: try ReleaseRuntimeIdentity.environmentFingerprint(
                toolchain: "native.release.tapeout-2.0.0"
            ),
            startedAt: startedAt,
            completedAt: now()
        )
        return TapeoutResult(
            schemaVersion: TapeoutRequest.currentSchemaVersion,
            runID: request.runID,
            status: status,
            diagnostics: diagnostics,
            artifacts: artifacts,
            metadata: metadata,
            payload: payload
        )
    }
}
