import Foundation
import PDKCore
import PhysicalDesignCore
import ReleaseCore
import XcircuitePackage

public struct DefaultTapeoutPackaging: TapeoutPackaging {
    private let streamOutValidator: any StreamOutValidating
    private let xorComparator: any LayoutXORComparing
    private let verifier: XcircuiteFileReferenceVerifier
    private let now: @Sendable () -> Date

    public init(
        streamOutValidator: any StreamOutValidating = DefaultStreamOutValidator(),
        xorComparator: any LayoutXORComparing = DefaultLayoutXORComparator(),
        verifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.streamOutValidator = streamOutValidator
        self.xorComparator = xorComparator
        self.verifier = verifier
        self.now = now
    }

    public func execute(
        _ request: TapeoutRequest
    ) async throws -> XcircuiteEngineResultEnvelope<TapeoutPayload> {
        let startedAt = now()
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "release.tapeout",
            implementationID: "native.release.tapeout",
            implementationVersion: "1.0.0",
            startedAt: startedAt,
            completedAt: now()
        )
        var diagnostics: [XcircuiteEngineDiagnostic] = []
        var status: XcircuiteEngineExecutionStatus = .completed
        var streamOutManifest: StreamOutManifest?
        var xorResult: LayoutXORResult?
        var handoff: FoundryHandoffManifest?

        func add(_ code: String, _ message: String, entity: String?, blocked: Bool) {
            diagnostics.append(XcircuiteEngineDiagnostic(
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
        if !bundle.approved {
            add("SIGNOFF_BUNDLE_NOT_APPROVED", "Tapeout accepts only a signoff bundle explicitly marked approved.", entity: bundle.artifact.path, blocked: true)
        }
        if !isSHA256(bundle.designDigest) || !isSHA256(bundle.pdkDigest) || !(bundle.bundleDigest.map(isSHA256) ?? false) {
            add("SIGNOFF_BUNDLE_DIGEST_REQUIRED", "Signoff bundle design, PDK, and bundle digests must be SHA-256 values.", entity: bundle.artifact.path, blocked: true)
        }
        if bundle.pdkDigest != request.pdk.digest {
            add("SIGNOFF_PDK_BINDING_MISMATCH", "Signoff bundle is bound to a different PDK revision.", entity: bundle.artifact.path, blocked: false)
        }
        if bundle.finalLayoutDigest != request.physicalDesign.layoutDigest {
            add("SIGNOFF_LAYOUT_BINDING_MISMATCH", "Signoff bundle is not bound to the exact final layout revision.", entity: bundle.artifact.path, blocked: false)
        }
        if bundle.artifact.sha256 == nil || bundle.artifact.byteCount == nil || bundle.artifact.path.isEmpty {
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
            if streamOut.requirements.requireExactStreamIdentity {
                add("LAYOUT_XOR_FAILED", xorResult?.message ?? "Layout XOR comparison failed.", entity: request.runID, blocked: false)
            } else {
                diagnostics.append(XcircuiteEngineDiagnostic(
                    severity: .warning,
                    code: "LAYOUT_XOR_GEOMETRY_NOT_QUALIFIED",
                    message: "Exact byte identity was not required, and no qualified geometric XOR comparator is installed.",
                    entity: request.runID,
                    suggestedActions: ["install_qualified_geometry_xor_comparator"]
                ))
            }
        }

        if let projectURL {
            let bundleIntegrity = verifier.verify(bundle.artifact, projectRoot: projectURL)
            if bundleIntegrity.status != .verified {
                add("SIGNOFF_BUNDLE_INTEGRITY_FAILED", bundleIntegrity.message, entity: bundle.artifact.path, blocked: true)
            }
            let pdkIntegrity = verifier.verify(request.pdk.manifest, projectRoot: projectURL)
            if pdkIntegrity.status != .verified {
                add("PDK_MANIFEST_INTEGRITY_FAILED", pdkIntegrity.message, entity: request.pdk.manifest.path, blocked: true)
            }
            for evidence in request.evidence {
                let integrity = verifier.verify(evidence, projectRoot: projectURL)
                if integrity.status != .verified {
                    add("HANDOFF_EVIDENCE_INTEGRITY_FAILED", integrity.message, entity: evidence.path, blocked: true)
                }
            }
        } else {
            add("HANDOFF_PROJECT_ROOT_REQUIRED", "A project root is required to verify signoff and handoff evidence artifacts.", entity: request.runID, blocked: true)
        }

        guard let releaseArtifact = request.releaseArtifact,
              releaseArtifact.kind == .release,
              !releaseArtifact.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              releaseArtifact.sha256 != nil,
              releaseArtifact.byteCount != nil else {
            add("TAPEOUT_RELEASE_ARTIFACT_REQUIRED", "Tapeout requires an immutable release artifact reference with digest and byte count.", entity: request.runID, blocked: true)
            return envelope(request: request, status: status, diagnostics: diagnostics, metadata: metadata, payload: TapeoutPayload(
                releaseArtifact: nil,
                checksum: nil,
                approved: false,
                signoffBundleDigest: bundle.bundleDigest,
                layoutDigest: request.physicalDesign.layoutDigest,
                pdkDigest: request.pdk.digest,
                streamOut: streamOutManifest,
                xorResult: xorResult
            ))
        }

        if status == .completed {
            let generatedAt = now()
            let evidenceIDs = request.evidence.compactMap { $0.artifactID ?? $0.path }
            let artifacts = uniqueArtifacts([
                bundle.artifact,
                request.physicalDesign.layoutArtifact,
                streamOut.manifest.streamedArtifact,
            ] + request.evidence + [releaseArtifact])
            let unsigned = FoundryHandoffManifest(
                releaseID: "\(request.runID)-tapeout",
                foundryID: request.foundryID,
                signoffBundleDigest: bundle.bundleDigest ?? "",
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
                signoffBundleDigest: unsigned.signoffBundleDigest,
                designDigest: unsigned.designDigest,
                pdkDigest: unsigned.pdkDigest,
                layoutDigest: unsigned.layoutDigest,
                artifacts: unsigned.artifacts,
                evidenceIDs: unsigned.evidenceIDs,
                generatedAt: unsigned.generatedAt,
                manifestDigest: unsigned.computedManifestDigest()
            )
        }

        let payload = TapeoutPayload(
            releaseArtifact: status == .completed ? releaseArtifact : nil,
            checksum: handoff?.manifestDigest,
            approved: status == .completed,
            signoffBundleDigest: bundle.bundleDigest,
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
            ] + request.evidence + [releaseArtifact]),
            metadata: metadata,
            payload: payload
        )
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
        }
    }

    private func uniqueArtifacts(_ artifacts: [XcircuiteFileReference]) -> [XcircuiteFileReference] {
        Array(Set(artifacts)).sorted { $0.path < $1.path }
    }

    private func envelope(
        request: TapeoutRequest,
        status: XcircuiteEngineExecutionStatus,
        diagnostics: [XcircuiteEngineDiagnostic],
        artifacts: [XcircuiteFileReference] = [],
        metadata: XcircuiteEngineExecutionMetadata,
        payload: TapeoutPayload
    ) -> XcircuiteEngineResultEnvelope<TapeoutPayload> {
        XcircuiteEngineResultEnvelope(
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
