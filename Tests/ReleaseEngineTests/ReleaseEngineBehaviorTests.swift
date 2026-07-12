import Foundation
import PDKCore
import PhysicalDesignCore
import ReleaseCore
import SignoffEngine
import TapeoutEngine
import Testing
import ToolQualification
import XcircuitePackage

@Suite("ReleaseEngine behavior")
struct ReleaseEngineBehaviorTests {
    private static let designDigest = String(repeating: "1", count: 64)
    private static let pdkDigest = String(repeating: "2", count: 64)
    private static let toolDigest = String(repeating: "3", count: 64)
    private static let bundleDigest = String(repeating: "4", count: 64)

    @Test("built-in profiles define digital, analog, and mixed-signal gates")
    func builtInProfiles() {
        let provider = DefaultSignoffProfileProvider()
        #expect(provider.profile(profileID: "digital")?.designKind == .digital)
        #expect(provider.profile(profileID: "analog")?.designKind == .analog)
        #expect(provider.profile(profileID: "mixed-signal")?.requirements.count == ReleaseSignoffAxis.allCases.count)
        #expect(provider.profile(profileID: "digital")?.requirement(for: .drc)?.required == true)
        #expect(provider.profile(profileID: "digital")?.requirement(for: .erc)?.required == false)
    }

    @Test("signoff blocks when typed evidence is absent")
    func missingEvidenceBlocks() async throws {
        let request = SignoffRequest(
            runID: "missing-evidence",
            inputs: [],
            profileID: "digital",
            designDigest: Self.designDigest,
            pdkDigest: Self.pdkDigest,
            evidence: [],
            projectRoot: FileManager.default.temporaryDirectory.path
        )
        let result = try await DefaultSignoffEvaluator().execute(request)
        #expect(result.status == .blocked)
        #expect(result.payload.approved == false)
        #expect(result.diagnostics.contains { $0.code == "EVIDENCE_RECORDS_REQUIRED" })
    }

    @Test("signoff approves a complete, integrity-verified evidence set")
    func completeSignoffProducesImmutableBundle() async throws {
        let root = try Self.makeTemporaryRoot(named: "release-signoff-pass")
        defer { Self.removeTemporaryRoot(root) }

        let reportArtifacts = try Self.makeReportArtifacts(root: root)
        let bundleArtifact = try Self.makeArtifact(
            root: root,
            relativePath: "release/signoff-bundle.json",
            data: Data("signoff bundle".utf8),
            kind: .release,
            format: .json
        )
        let records = ReleaseSignoffAxis.allCases.compactMap { axis -> ReleaseSignoffEvidenceReference? in
            guard let artifact = reportArtifacts[axis] else { return nil }
            let level: ToolQualificationLevel = axis == .simulation ? .smokeChecked : .corpusChecked
            return ReleaseSignoffEvidenceReference(
                evidenceID: "evidence-\(axis.rawValue)",
                axis: axis,
                artifact: artifact,
                designDigest: Self.designDigest,
                pdkDigest: Self.pdkDigest,
                toolID: "native-\(axis.rawValue)",
                toolDigest: Self.toolDigest,
                qualificationLevel: level,
                disposition: .passed
            )
        }
        let request = SignoffRequest(
            runID: "complete-signoff",
            inputs: Array(reportArtifacts.values) + [bundleArtifact],
            profileID: "digital",
            designDigest: Self.designDigest,
            pdkDigest: Self.pdkDigest,
            evidence: Array(reportArtifacts.values),
            designKind: .digital,
            evidenceRecords: records,
            projectRoot: root.path,
            finalLayoutDigest: String(repeating: "5", count: 64),
            bundleArtifact: bundleArtifact
        )
        let result = try await DefaultSignoffEvaluator().execute(request)
        #expect(result.status == .completed)
        #expect(result.payload.approved)
        #expect(result.payload.bundle?.finalLayoutDigest == request.finalLayoutDigest)
        #expect(result.payload.bundle?.bundleDigest != nil)
        #expect(result.payload.axisResults.contains { $0.disposition == .profileApprovedNotApplicable })
        #expect(result.payload.axisResults.filter { $0.disposition == .passed }.count == 6)
    }

    @Test("an expired or invalid waiver cannot turn a failed axis into approval")
    func invalidWaiverBlocks() async throws {
        let root = try Self.makeTemporaryRoot(named: "release-signoff-waiver")
        defer { Self.removeTemporaryRoot(root) }
        let reportArtifacts = try Self.makeReportArtifacts(root: root)
        let bundleArtifact = try Self.makeArtifact(root: root, relativePath: "release/signoff-bundle.json", data: Data("bundle".utf8), kind: .release, format: .json)
        let records = ReleaseSignoffAxis.allCases.compactMap { axis -> ReleaseSignoffEvidenceReference? in
            guard let artifact = reportArtifacts[axis] else { return nil }
            return ReleaseSignoffEvidenceReference(
                evidenceID: "evidence-\(axis.rawValue)",
                axis: axis,
                artifact: artifact,
                designDigest: Self.designDigest,
                pdkDigest: Self.pdkDigest,
                toolID: "tool",
                toolDigest: Self.toolDigest,
                qualificationLevel: axis == .simulation ? .smokeChecked : .corpusChecked,
                disposition: axis == .simulation ? .failed : .passed,
                reason: axis == .simulation ? "Simulation regression" : nil
            )
        }
        let old = Date(timeIntervalSince1970: 1_000)
        let waiver = SignoffWaiver(
            waiverID: "expired-waiver",
            axis: .simulation,
            reason: "Expired exception",
            authority: "review-board",
            approvedAt: old,
            expiresAt: old.addingTimeInterval(10),
            affectedEvidenceIDs: ["evidence-simulation"],
            designDigest: Self.designDigest,
            pdkDigest: Self.pdkDigest
        )
        let request = SignoffRequest(
            runID: "invalid-waiver",
            inputs: Array(reportArtifacts.values) + [bundleArtifact],
            profileID: "digital",
            designDigest: Self.designDigest,
            pdkDigest: Self.pdkDigest,
            evidence: Array(reportArtifacts.values),
            evidenceRecords: records,
            waivers: [waiver],
            projectRoot: root.path,
            finalLayoutDigest: String(repeating: "5", count: 64),
            bundleArtifact: bundleArtifact
        )
        var validWaiver = waiver
        validWaiver.expiresAt = Date(timeIntervalSince1970: 3_000)
        var validRequest = request
        validRequest.runID = "valid-waiver"
        validRequest.waivers = [validWaiver]
        let validResult = try await DefaultSignoffEvaluator(now: { Date(timeIntervalSince1970: 2_000) }).execute(validRequest)
        #expect(validResult.status == .completed)
        #expect(validResult.payload.approved)
        #expect(validResult.payload.axisResults.contains { $0.disposition == .waived })

        let result = try await DefaultSignoffEvaluator(now: { Date(timeIntervalSince1970: 2_000) }).execute(request)
        #expect(result.status == .blocked)
        #expect(result.payload.approved == false)
        #expect(result.diagnostics.contains { $0.code == "WAIVER_EXPIRED_OR_INVALID" })
    }

    @Test("tapeout requires exact signoff, PDK, layout, and stream-out bindings")
    func tapeoutProducesReproducibleHandoff() async throws {
        let root = try Self.makeTemporaryRoot(named: "release-tapeout-pass")
        defer { Self.removeTemporaryRoot(root) }
        let report = try Self.makeArtifact(root: root, relativePath: "reports/drc.json", data: Data("report".utf8), kind: .report, format: .json)
        let pdkManifest = try Self.makeArtifact(root: root, relativePath: "pdk/manifest.json", data: Data("pdk".utf8), kind: .technology, format: .json)
        let layoutData = Data([0, 6, 0, 2, 0, 4, 0, 0, 0, 0])
        let layout = try Self.makeArtifact(root: root, relativePath: "layout/top.gds", data: layoutData, kind: .layout, format: .gdsii)
        let bundleArtifact = try Self.makeArtifact(root: root, relativePath: "release/signoff.json", data: Data("bundle".utf8), kind: .release, format: .json)
        let releaseArtifact = try Self.makeArtifact(root: root, relativePath: "release/tapeout.json", data: Data("handoff".utf8), kind: .release, format: .json)
        let physical = PhysicalDesignReference(layoutArtifact: layout, topCell: "TOP", layoutDigest: layout.sha256 ?? "")
        let pdk = PDKReference(manifest: pdkManifest, processID: "sky130", version: "1", digest: Self.pdkDigest)
        let requirements = TapeoutReleaseRequirements(
            expectedTopCell: "TOP",
            expectedUnitsPerDatabaseUnit: 0.001,
            requiredLayerIDs: ["M1"],
            requiredPadCells: ["PAD"],
            requiredSeal: "release-seal"
        )
        let manifest = StreamOutManifest(
            streamedArtifact: layout,
            topCell: "TOP",
            unitsPerDatabaseUnit: 0.001,
            layerMap: ["M1": 1],
            hierarchyDepth: 1,
            seal: "release-seal",
            padCells: ["PAD"],
            generatedBy: "native-stream-out"
        )
        let request = TapeoutRequest(
            runID: "complete-tapeout",
            inputs: [layout, report, pdkManifest, bundleArtifact],
            signoffBundle: SignoffBundleReference(
                artifact: bundleArtifact,
                designDigest: Self.designDigest,
                pdkDigest: Self.pdkDigest,
                finalLayoutDigest: physical.layoutDigest,
                bundleDigest: Self.bundleDigest,
                approved: true
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
        let result = try await DefaultTapeoutPackaging().execute(request)
        #expect(result.status == .completed)
        #expect(result.payload.approved)
        #expect(result.payload.xorResult?.status == .passed)
        #expect(result.payload.handoff?.isSelfConsistent == true)
        #expect(result.payload.checksum == result.payload.handoff?.manifestDigest)
    }

    @Test("tapeout blocks when stream-out integrity is unavailable")
    func tapeoutBlocksMissingProjectRoot() async throws {
        let layout = XcircuiteFileReference(path: "layout/top.gds", kind: .layout, format: .gdsii, sha256: String(repeating: "a", count: 64), byteCount: 10)
        let physical = PhysicalDesignReference(layoutArtifact: layout, topCell: "TOP", layoutDigest: layout.sha256 ?? "")
        let bundle = XcircuiteFileReference(path: "release/signoff.json", kind: .release, format: .json, sha256: String(repeating: "b", count: 64), byteCount: 1)
        let request = TapeoutRequest(
            runID: "blocked-tapeout",
            inputs: [],
            signoffBundle: SignoffBundleReference(artifact: bundle, designDigest: Self.designDigest, pdkDigest: Self.pdkDigest, finalLayoutDigest: physical.layoutDigest, bundleDigest: Self.bundleDigest),
            physicalDesign: physical,
            pdk: PDKReference(manifest: bundle, processID: "p", version: "1", digest: Self.pdkDigest),
            foundryID: "foundry",
            releaseArtifact: bundle
        )
        let result = try await DefaultTapeoutPackaging().execute(request)
        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code == "STREAM_OUT_REQUIRED" })
    }

    private static func makeReportArtifacts(root: URL) throws -> [ReleaseSignoffAxis: XcircuiteFileReference] {
        var result: [ReleaseSignoffAxis: XcircuiteFileReference] = [:]
        for axis in ReleaseSignoffAxis.allCases {
            result[axis] = try makeArtifact(
                root: root,
                relativePath: "reports/\(axis.rawValue).json",
                data: Data("{\"axis\":\"\(axis.rawValue)\"}".utf8),
                kind: .report,
                format: .json
            )
        }
        return result
    }

    private static func makeArtifact(
        root: URL,
        relativePath: String,
        data: Data,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference {
        let url = root.appending(path: relativePath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            throw error
        }
        return XcircuiteFileReference(
            artifactID: relativePath.replacingOccurrences(of: "/", with: "-"),
            path: relativePath,
            kind: kind,
            format: format,
            sha256: XcircuiteHasher().sha256(data: data),
            byteCount: Int64(data.count)
        )
    }

    private static func makeTemporaryRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "release-engine-(name)-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw error
        }
        return root
    }

    private static func removeTemporaryRoot(_ root: URL) {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            // Test cleanup is best effort and does not affect the assertion result.
        }
    }
}
