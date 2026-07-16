import Foundation
import PDKCore
import PhysicalDesignCore
import ReleaseCore
import CircuiteFoundation

public struct DefaultTapeoutPackaging: TapeoutPackaging {
    private let streamOutValidator: any StreamOutValidating
    private let xorComparator: any LayoutXORComparing
    private let verifier: LocalArtifactVerifier
    private let now: @Sendable () -> Date

    public init(
        streamOutValidator: any StreamOutValidating = DefaultStreamOutValidator(),
        xorComparator: any LayoutXORComparing = DefaultLayoutXORComparator(),
        verifier: LocalArtifactVerifier = LocalArtifactVerifier(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.streamOutValidator = streamOutValidator
        self.xorComparator = xorComparator
        self.verifier = verifier
        self.now = now
    }

    public func execute(
        _ request: TapeoutRequest
    ) async throws -> TapeoutResult {
        let startedAt = now()
        let metadata = try ExecutionProvenance(
            engineID: "release.tapeout",
            implementationID: "native.release.tapeout",
            implementationVersion: "1.0.0",
            startedAt: startedAt,
            completedAt: now()
        )
        var diagnostics: [DesignDiagnostic] = []
        var status: ReleaseExecutionStatus = .completed
        var streamOutManifest: StreamOutManifest?
        var xorResult: LayoutXORResult?
        var handoff: FoundryHandoffManifest?

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
            return envelope(request: request, status: status, diagnostics: diagnostics, metadata: metadata, payload: TapeoutPayload(releaseArtifact: nil, checksum: nil))
        }
        guard !request.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            add("RUN_ID_REQUIRED", "Tapeout run ID must not be empty.", entity: nil, blocked: true)
            return envelope(request: request, status: status, diagnostics: diagnostics, metadata: metadata, payload: TapeoutPayload(releaseArtifact: nil, checksum: nil))
        }
        guard !request.foundryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            add("FOUNDRY_ID_REQUIRED", "Foundry ID is required for handoff.", entity: request.runID, blocked: true)
            return envelope(request: request, status: status, diagnostics: diagnostics, metadata: metadata, payload: TapeoutPayload(releaseArtifact: nil, checksum: nil))
        }

        let bundle = request.signoffBundle
        if bundle.artifact.kind != .release {
            add("SIGNOFF_BUNDLE_KIND_INVALID", "Tapeout accepts only a release-kind signoff bundle artifact.", entity: bundle.artifact.path, blocked: true)
        }
        if !isSHA256(bundle.designDigest) || !isSHA256(bundle.pdkDigest) {
            add("SIGNOFF_BUNDLE_DIGEST_REQUIRED", "Signoff bundle design and PDK digests must be SHA-256 values.", entity: bundle.artifact.path, blocked: true)
        }
        if bundle.pdkDigest != request.pdk.digest {
            add("SIGNOFF_PDK_BINDING_MISMATCH", "Signoff bundle is bound to a different PDK revision.", entity: bundle.artifact.path, blocked: false)
        }
        if bundle.finalLayoutDigest != request.physicalDesign.layoutDigest {
            add("SIGNOFF_LAYOUT_BINDING_MISMATCH", "Signoff bundle is not bound to the exact final layout revision.", entity: bundle.artifact.path, blocked: false)
        }
        if bundle.artifact.byteCount == 0 || bundle.artifact.path.isEmpty {
            add("SIGNOFF_BUNDLE_ARTIFACT_INCOMPLETE", "Signoff bundle artifact reference must include path, SHA-256, and byte count.", entity: bundle.artifact.path, blocked: true)
        }
        if request.pdk.manifest.kind != .technology {
            add("PDK_MANIFEST_KIND_INVALID", "PDK reference must point to a technology manifest artifact.", entity: request.pdk.manifest.path, blocked: true)
        }

        guard let streamOut = request.streamOut else {
            add("STREAM_OUT_REQUIRED", "Tapeout requires a validated stream-out manifest.", entity: request.runID, blocked: true)
            return envelope(request: request, status: status, diagnostics: diagnostics, metadata: metadata, payload: TapeoutPayload(releaseArtifact: nil, checksum: nil))
        }
        streamOutManifest = streamOut.manifest
        let validation = streamOutValidator.validate(streamOut)
        diagnostics.append(contentsOf: validation.diagnostics)
        switch validation.status {
        case .blocked:
            status = .blocked
        case .failed where status != .blocked:
            status = .failed
        case .passed, .failed:
            break
        }

        let projectRoot = request.projectRoot ?? streamOut.projectRoot
        let projectURL = projectRoot.map(URL.init(fileURLWithPath:))
        xorResult = xorComparator.compare(
            source: request.physicalDesign.layoutArtifact,
            streamed: streamOut.manifest.streamedArtifact,
            projectRoot: projectURL
        )
        if xorResult?.status == .blocked {
            add("LAYOUT_XOR_BLOCKED", xorResult?.message ?? "Layout XOR comparison is blocked.", entity: request.runID, blocked: true)
        } else if xorResult?.status == .failed {
            add("LAYOUT_XOR_FAILED", xorResult?.message ?? "Layout comparison failed.", entity: request.runID, blocked: false)
        } else if xorResult?.isTapeoutQualified(at: startedAt) != true {
            add(
                "LAYOUT_XOR_QUALIFICATION_REQUIRED",
                "Tapeout requires byte-identical layout streams or immutable evidence from a production-qualified geometric XOR implementation.",
                entity: request.runID,
                blocked: true
            )
        }

        if let projectURL {
            let bundleIntegrity = verifier.verify(bundle.artifact, relativeTo: projectURL)
            if !bundleIntegrity.isVerified {
                add("SIGNOFF_BUNDLE_INTEGRITY_FAILED", bundleIntegrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; "), entity: bundle.artifact.path, blocked: true)
            } else {
                do {
                    let bundleURL = try bundle.artifact.locator.location.resolvedFileURL(relativeTo: projectURL)
                    let persistedBundle = try SignoffBundle.decodeCanonical(from: Data(contentsOf: bundleURL))
                    guard persistedBundle.designDigest == bundle.designDigest,
                          persistedBundle.pdkDigest == bundle.pdkDigest,
                          persistedBundle.finalLayoutDigest == bundle.finalLayoutDigest else {
                        add("SIGNOFF_BUNDLE_CONTENT_MISMATCH", "The persisted signoff bundle does not match its artifact reference and release bindings.", entity: bundle.artifact.path, blocked: true)
                        return envelope(request: request, status: status, diagnostics: diagnostics, metadata: metadata, payload: TapeoutPayload(releaseArtifact: nil, checksum: nil))
                    }
                } catch {
                    add("SIGNOFF_BUNDLE_DECODE_FAILED", "The persisted signoff bundle is not canonical: \(error.localizedDescription)", entity: bundle.artifact.path, blocked: true)
                }
            }
            let pdkIntegrity = verifier.verify(request.pdk.manifest, relativeTo: projectURL)
            if !pdkIntegrity.isVerified {
                add("PDK_MANIFEST_INTEGRITY_FAILED", pdkIntegrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; "), entity: request.pdk.manifest.path, blocked: true)
            }
            for evidence in request.evidence {
                let integrity = verifier.verify(evidence, relativeTo: projectURL)
                if !integrity.isVerified {
                    add("HANDOFF_EVIDENCE_INTEGRITY_FAILED", integrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; "), entity: evidence.path, blocked: true)
                }
            }
            if let xorEvidence = xorResult?.evidenceArtifact {
                let integrity = verifier.verify(xorEvidence, relativeTo: projectURL)
                if !integrity.isVerified {
                    add("LAYOUT_XOR_EVIDENCE_INTEGRITY_FAILED", integrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; "), entity: xorEvidence.path, blocked: true)
                }
            }
            if let qualification = xorResult?.processQualification {
                let qualificationArtifacts = qualification.identityArtifacts.all
                    + qualification.evidenceArtifacts
                    + qualification.inputArtifacts
                    + qualification.outputArtifacts
                for artifact in Set(qualificationArtifacts) {
                    let integrity = verifier.verify(artifact, relativeTo: projectURL)
                    if !integrity.isVerified {
                        add(
                            "LAYOUT_XOR_QUALIFICATION_INTEGRITY_FAILED",
                            integrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; "),
                            entity: artifact.path,
                            blocked: true
                        )
                    }
                }
            }
        } else {
            add("HANDOFF_PROJECT_ROOT_REQUIRED", "A project root is required to verify signoff and handoff evidence artifacts.", entity: request.runID, blocked: true)
        }

        guard let releaseArtifact = request.releaseArtifact,
              releaseArtifact.kind == .release,
              !releaseArtifact.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              releaseArtifact.byteCount > 0 else {
            add("TAPEOUT_RELEASE_ARTIFACT_REQUIRED", "Tapeout requires an immutable release artifact reference with digest and byte count.", entity: request.runID, blocked: true)
            return envelope(request: request, status: status, diagnostics: diagnostics, metadata: metadata, payload: TapeoutPayload(
                releaseArtifact: nil,
                checksum: nil,
                completed: false,
                layoutDigest: request.physicalDesign.layoutDigest,
                pdkDigest: request.pdk.digest,
                streamOut: streamOutManifest,
                xorResult: xorResult
            ))
        }

        if status == .completed {
            let generatedAt = now()
            let evidenceIDs = request.evidence.map(\.artifactID)
            let artifacts = uniqueArtifacts([
                bundle.artifact,
                request.pdk.manifest,
                request.physicalDesign.layoutArtifact,
                streamOut.manifest.streamedArtifact,
            ] + request.evidence + [xorResult?.evidenceArtifact].compactMap { $0 })
            let unsigned = FoundryHandoffManifest(
                releaseID: "\(request.runID)-tapeout",
                foundryID: request.foundryID,
                signoffBundleArtifactDigest: bundle.artifact.sha256,
                designDigest: bundle.designDigest,
                pdkDigest: request.pdk.digest,
                layoutDigest: request.physicalDesign.layoutDigest,
                artifacts: artifacts,
                evidenceIDs: evidenceIDs,
                generatedAt: generatedAt,
                manifestDigest: ""
            )
            handoff = FoundryHandoffManifest(
                releaseID: unsigned.releaseID,
                foundryID: unsigned.foundryID,
                signoffBundleArtifactDigest: unsigned.signoffBundleArtifactDigest,
                designDigest: unsigned.designDigest,
                pdkDigest: unsigned.pdkDigest,
                layoutDigest: unsigned.layoutDigest,
                artifacts: unsigned.artifacts,
                evidenceIDs: unsigned.evidenceIDs,
                generatedAt: unsigned.generatedAt,
                manifestDigest: unsigned.computedManifestDigest()
            )
            if let expectedHandoff = handoff, let projectURL {
                let integrity = verifier.verify(releaseArtifact, relativeTo: projectURL)
                if !integrity.isVerified {
                    add(
                        "TAPEOUT_RELEASE_ARTIFACT_INTEGRITY_FAILED",
                        integrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; "),
                        entity: releaseArtifact.path,
                        blocked: true
                    )
                    handoff = nil
                } else {
                    do {
                        let url = try releaseArtifact.locator.location.resolvedFileURL(relativeTo: projectURL)
                        let data = try Data(contentsOf: url)
                        let decoded = try FoundryHandoffManifest.decodeCanonical(from: data)
                        let expected = try expectedHandoff.canonicalData()
                        guard decoded == expectedHandoff,
                              decoded.isSelfConsistent,
                              data == expected,
                              releaseArtifact.byteCount == UInt64(expected.count) else {
                            add(
                                "TAPEOUT_RELEASE_ARTIFACT_CONTENT_MISMATCH",
                                "Release artifact bytes do not equal the canonical foundry handoff manifest.",
                                entity: releaseArtifact.path,
                                blocked: true
                            )
                            handoff = nil
                            return envelope(request: request, status: status, diagnostics: diagnostics, metadata: metadata, payload: TapeoutPayload(releaseArtifact: nil, checksum: nil))
                        }
                    } catch {
                        add(
                            "TAPEOUT_RELEASE_ARTIFACT_DECODE_FAILED",
                            error.localizedDescription,
                            entity: releaseArtifact.path,
                            blocked: true
                        )
                        handoff = nil
                    }
                }
            }
        }

        let payload = TapeoutPayload(
            releaseArtifact: status == .completed ? releaseArtifact : nil,
            checksum: handoff?.manifestDigest,
            completed: status == .completed,
            layoutDigest: request.physicalDesign.layoutDigest,
            pdkDigest: request.pdk.digest,
            streamOut: streamOutManifest,
            xorResult: xorResult,
            handoff: handoff
        )
        return envelope(
            request: request,
            status: status,
            diagnostics: diagnostics,
            artifacts: uniqueArtifacts([
                bundle.artifact,
                request.pdk.manifest,
                request.physicalDesign.layoutArtifact,
                streamOut.manifest.streamedArtifact,
            ] + request.evidence + [xorResult?.evidenceArtifact, releaseArtifact].compactMap { $0 }),
            metadata: metadata,
            payload: payload
        )
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
        }
    }

    private func uniqueArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        Array(Set(artifacts)).sorted { $0.path < $1.path }
    }

    private func envelope(
        request: TapeoutRequest,
        status: ReleaseExecutionStatus,
        diagnostics: [DesignDiagnostic],
        artifacts: [ArtifactReference] = [],
        metadata: ExecutionProvenance,
        payload: TapeoutPayload
    ) -> TapeoutResult {
        TapeoutResult(
            schemaVersion: TapeoutRequest.currentSchemaVersion,
            runID: request.runID,
            status: status,
            diagnostics: diagnostics,
            artifacts: payload.handoff?.artifacts ?? artifacts,
            metadata: metadata,
            payload: payload
        )
    }
}
