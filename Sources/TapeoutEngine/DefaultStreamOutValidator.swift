import Foundation
import ReleaseCore
import CircuiteFoundation

public struct DefaultStreamOutValidator: StreamOutValidating {
    private let artifactReader: any ReleaseArtifactReading

    public init(
        artifactReader: any ReleaseArtifactReading = LocalReleaseArtifactStore()
    ) {
        self.artifactReader = artifactReader
    }

    public func validate(_ request: StreamOutRequest) async -> StreamOutValidationResult {
        var diagnostics: [DesignDiagnostic] = []
        var status: LayoutXORStatus = .passed

        func fail(_ code: String, _ message: String, entity: String?, blocked: Bool) {
            diagnostics.append(DesignDiagnostic(
                severity: .error,
                code: code,
                message: message,
                entity: entity,
                suggestedActions: ["inspect_stream_out_manifest", "rerun_stream_out"]
            ))
            if blocked {
                status = .blocked
            } else if status != .blocked {
                status = .failed
            }
        }

        guard request.schemaVersion == StreamOutRequest.currentSchemaVersion else {
            fail("INVALID_STREAM_OUT_SCHEMA", "Unsupported stream-out request schema version.", entity: nil, blocked: true)
            return StreamOutValidationResult(status: status, diagnostics: diagnostics)
        }
        guard request.manifest.schemaVersion == StreamOutManifest.currentSchemaVersion else {
            fail("INVALID_STREAM_OUT_MANIFEST_SCHEMA", "Unsupported stream-out manifest schema version.", entity: nil, blocked: true)
            return StreamOutValidationResult(status: status, diagnostics: diagnostics)
        }
        guard let projectRoot = request.projectRoot.map(URL.init(fileURLWithPath:)) else {
            fail("STREAM_OUT_PROJECT_ROOT_REQUIRED", "A project root is required to verify source and streamed layout artifacts.", entity: nil, blocked: true)
            return StreamOutValidationResult(status: status, diagnostics: diagnostics)
        }

        let source = request.sourceLayout
        let manifest = request.manifest
        let requirements = request.requirements
        let sourceFormat = source.layoutArtifact.descriptor.format
        let streamedFormat = manifest.streamedArtifact.descriptor.format
        guard sourceFormat == .gdsii || sourceFormat == .oasis else {
            fail("UNSUPPORTED_SOURCE_LAYOUT_FORMAT", "Source layout must use GDSII or OASIS.", entity: source.layoutArtifact.reference.id.description, blocked: true)
            return StreamOutValidationResult(status: status, diagnostics: diagnostics)
        }
        guard streamedFormat == sourceFormat else {
            fail("STREAM_OUT_FORMAT_MISMATCH", "Streamed layout format must match the source layout format.", entity: manifest.streamedArtifact.reference.id.description, blocked: false)
            return StreamOutValidationResult(status: status, diagnostics: diagnostics)
        }
        if source.topCell != requirements.expectedTopCell || manifest.topCell != requirements.expectedTopCell {
            fail("TOP_CELL_MISMATCH", "Source, stream-out manifest, and release requirements must use the same top cell.", entity: requirements.expectedTopCell, blocked: false)
        }
        if !manifest.unitsPerDatabaseUnit.isFinite || manifest.unitsPerDatabaseUnit <= 0 {
            fail("INVALID_STREAM_OUT_UNITS", "Stream-out units must be finite and greater than zero.", entity: manifest.topCell, blocked: false)
        }
        if manifest.unitsPerDatabaseUnit != requirements.expectedUnitsPerDatabaseUnit {
            fail("STREAM_OUT_UNITS_MISMATCH", "Stream-out units do not match the release requirements.", entity: manifest.topCell, blocked: false)
        }
        if manifest.hierarchyDepth <= 0 {
            fail("INVALID_HIERARCHY_DEPTH", "Stream-out hierarchy depth must be greater than zero.", entity: manifest.topCell, blocked: false)
        }
        if manifest.layerMap.isEmpty {
            fail("LAYER_MAP_REQUIRED", "A non-empty layer map is required for foundry handoff.", entity: manifest.topCell, blocked: false)
        }
        if Set(manifest.layerMap.keys).count != manifest.layerMap.count || Set(manifest.layerMap.values).count != manifest.layerMap.values.count {
            fail("LAYER_MAP_NOT_UNIQUE", "Layer map IDs and target layers must be unique.", entity: manifest.topCell, blocked: false)
        }
        let missingLayers = requirements.requiredLayerIDs.filter { manifest.layerMap[$0] == nil }
        if !missingLayers.isEmpty {
            fail("REQUIRED_LAYER_MISSING", "Required layers are absent from the stream-out layer map: \(missingLayers.sorted().joined(separator: ", ")).", entity: manifest.topCell, blocked: false)
        }
        let missingPads = requirements.requiredPadCells.filter { !manifest.padCells.contains($0) }
        if !missingPads.isEmpty {
            fail("REQUIRED_PAD_CELL_MISSING", "Required pad cells are absent from the stream-out manifest: \(missingPads.sorted().joined(separator: ", ")).", entity: manifest.topCell, blocked: false)
        }
        if manifest.seal != requirements.requiredSeal {
            fail("RELEASE_SEAL_MISMATCH", "Stream-out seal does not match the release requirements.", entity: manifest.topCell, blocked: false)
        }
        if manifest.generatedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fail("STREAM_OUT_PRODUCER_REQUIRED", "Stream-out manifest must identify the generator.", entity: manifest.topCell, blocked: true)
        }
        if source.layoutArtifact.reference.digest.algorithm != .sha256
            || source.layoutDigest != source.layoutArtifact.reference.digest.hexadecimalValue {
            fail("SOURCE_LAYOUT_DIGEST_MISMATCH", "Physical design layout digest does not match its artifact reference.", entity: source.layoutArtifact.reference.id.description, blocked: false)
        }

        do {
            let sourceBinding = try ReleaseArtifactBinding(
                logicalID: source.layoutArtifact.logicalID,
                reference: source.layoutArtifact.reference,
                availability: source.layoutArtifact.availability
            )
            let sourceData = try await artifactReader.load(sourceBinding, relativeTo: projectRoot)
            let streamedData = try await artifactReader.load(
                manifest.streamedArtifact,
                relativeTo: projectRoot
            )
            if !hasValidSignature(sourceData, format: sourceFormat) {
                fail("SOURCE_LAYOUT_SIGNATURE_INVALID", "Source layout bytes do not contain the expected GDSII or OASIS signature.", entity: source.layoutArtifact.reference.id.description, blocked: false)
            }
            if !hasValidSignature(streamedData, format: streamedFormat) {
                fail("STREAMED_LAYOUT_SIGNATURE_INVALID", "Streamed layout bytes do not contain the expected GDSII or OASIS signature.", entity: manifest.streamedArtifact.reference.id.description, blocked: false)
            }
        } catch {
            fail("STREAM_OUT_ARTIFACT_INTEGRITY_FAILED", "Source or streamed layout bytes failed exact binding verification: \(error.localizedDescription)", entity: manifest.topCell, blocked: true)
        }

        return StreamOutValidationResult(status: status, diagnostics: diagnostics)
    }

    private func hasValidSignature(_ data: Data, format: ArtifactFormat) -> Bool {
        switch format {
        case .oasis:
            data.starts(with: Data("%SEMI-OASIS".utf8))
        case .gdsii:
            data.count >= 4 && data[data.startIndex] == 0 && data[data.startIndex + 1] == 6
                && data[data.startIndex + 2] == 0 && data[data.startIndex + 3] == 2
        default:
            false
        }
    }
}
