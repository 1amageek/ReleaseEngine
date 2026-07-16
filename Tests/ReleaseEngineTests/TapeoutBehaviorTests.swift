import CircuiteFoundation
import Foundation
import PDKCore
import PhysicalDesignCore
import ReleaseCore
import TapeoutEngine
import Testing

@Suite("Tapeout behavior")
struct TapeoutBehaviorTests {
    @Test("tapeout reproduces exact signoff, PDK, layout, stream-out, and handoff bindings")
    func exactBindings() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }

        let result = try await DefaultTapeoutPackaging(now: { fixture.generatedAt }).execute(fixture.request)

        #expect(result.status == .completed)
        #expect(result.payload.completed)
        #expect(result.payload.xorResult?.method == .byteIdentity)
        #expect(result.payload.handoff?.isSelfConsistent == true)
        #expect(result.payload.releaseArtifact == fixture.request.releaseArtifact)
    }

    @Test("missing project root blocks integrity verification")
    func missingIntegrityContext() async throws {
        let fixture = try TapeoutFixture()
        defer { fixture.remove() }
        let original = fixture.request
        let streamOut = try #require(original.streamOut)
        let request = TapeoutRequest(
            runID: original.runID,
            inputs: original.inputs,
            signoffBundle: original.signoffBundle,
            physicalDesign: original.physicalDesign,
            pdk: original.pdk,
            streamOut: StreamOutRequest(
                sourceLayout: streamOut.sourceLayout,
                manifest: streamOut.manifest,
                requirements: streamOut.requirements
            ),
            foundryID: original.foundryID,
            releaseArtifact: original.releaseArtifact,
            evidence: original.evidence
        )

        let result = try await DefaultTapeoutPackaging().execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "STREAM_OUT_PROJECT_ROOT_REQUIRED" })
        #expect(result.diagnostics.contains { $0.code.rawValue == "HANDOFF_PROJECT_ROOT_REQUIRED" })
    }
}

private struct TapeoutFixture {
    let root: URL
    let generatedAt = Date(timeIntervalSince1970: 2_000)
    let request: TapeoutRequest

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "tapeout-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pdkDigest = String(repeating: "2", count: 64)
        let designDigest = String(repeating: "1", count: 64)
        let layout = try Self.write(
            Data([0, 6, 0, 2, 0, 4, 0, 0, 0, 0]),
            path: "layout/top.gds",
            kind: .layout,
            format: .gdsii,
            root: root
        )
        let pdkManifest = try Self.write(
            Data("pdk".utf8),
            path: "pdk/manifest.json",
            kind: .technology,
            format: .json,
            root: root
        )
        let report = try Self.write(
            Data("report".utf8),
            path: "reports/drc.json",
            kind: .report,
            format: .json,
            root: root
        )
        let bundle = SignoffBundle(
            bundleID: "bundle",
            profileID: "digital",
            designDigest: designDigest,
            pdkDigest: pdkDigest,
            finalLayoutDigest: layout.sha256,
            axisResults: ReleaseSignoffAxis.allCases.map {
                SignoffAxisResult(axis: $0, disposition: .passed, evidenceIDs: ["e-\($0.rawValue)"], reason: "passed")
            },
            waivers: [],
            evidenceDigest: String(repeating: "3", count: 64),
            issuedAt: generatedAt.addingTimeInterval(-1)
        )
        let bundleArtifact = try Self.write(
            try bundle.canonicalData(),
            path: "release/signoff.json",
            kind: .release,
            format: .json,
            root: root
        )
        let physical = PhysicalDesignReference(layoutArtifact: layout, topCell: "TOP", layoutDigest: layout.sha256)
        let pdk = PDKReference(manifest: pdkManifest, processID: "process", version: "1", digest: pdkDigest)
        let requirements = TapeoutReleaseRequirements(
            expectedTopCell: "TOP",
            expectedUnitsPerDatabaseUnit: 0.001,
            requiredLayerIDs: ["M1"],
            requiredPadCells: ["PAD"],
            requiredSeal: "seal"
        )
        let manifest = StreamOutManifest(
            streamedArtifact: layout,
            topCell: "TOP",
            unitsPerDatabaseUnit: 0.001,
            layerMap: ["M1": 1],
            hierarchyDepth: 1,
            seal: "seal",
            padCells: ["PAD"],
            generatedBy: "native"
        )
        let artifacts = [bundleArtifact, pdkManifest, layout, report]
            .reduce(into: [ArtifactReference]()) { result, artifact in
                if !result.contains(artifact) { result.append(artifact) }
            }
            .sorted { $0.path < $1.path }
        let unsigned = FoundryHandoffManifest(
            releaseID: "tapeout-tapeout",
            foundryID: "foundry",
            signoffBundleArtifactDigest: bundleArtifact.sha256,
            designDigest: designDigest,
            pdkDigest: pdkDigest,
            layoutDigest: layout.sha256,
            artifacts: artifacts,
            evidenceIDs: [report.artifactID],
            generatedAt: generatedAt,
            manifestDigest: ""
        )
        let handoff = FoundryHandoffManifest(
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
        let releaseArtifact = try Self.write(
            try handoff.canonicalData(),
            path: "release/handoff.json",
            kind: .release,
            format: .json,
            root: root
        )
        request = TapeoutRequest(
            runID: "tapeout",
            inputs: artifacts,
            signoffBundle: SignoffBundleReference(
                artifact: bundleArtifact,
                designDigest: designDigest,
                pdkDigest: pdkDigest,
                finalLayoutDigest: layout.sha256
            ),
            physicalDesign: physical,
            pdk: pdk,
            streamOut: StreamOutRequest(
                sourceLayout: physical,
                manifest: manifest,
                projectRoot: root.path,
                requirements: requirements
            ),
            foundryID: "foundry",
            projectRoot: root.path,
            releaseArtifact: releaseArtifact,
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

    private static func write(
        _ data: Data,
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        root: URL
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
            relativeTo: root
        )
    }
}
