import Foundation
import QualificationEngine
import Testing
import ToolQualification
import XcircuitePackage

@Suite("Retained qualification")
struct RetainedQualificationTests {
    private static let evaluationDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("qualified retained corpus produces a process-scoped result")
    func qualifiedCorpusProducesResult() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-pass")
        defer { Self.removeTemporaryRoot(root) }

        let request = try Self.makeRequest(root: root, laneKind: .nativeCorpus)
        let encoded = try Self.encode(request)
        let decoded = try JSONDecoder().decode(ReleaseQualificationRequest.self, from: encoded)
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(decoded)

        #expect(result.status == .completed)
        #expect(result.payload.qualified)
        #expect(result.payload.qualificationLevel == .corpusChecked)
        #expect(result.payload.qualificationScope?.processProfileID == "sky130")
        #expect(result.payload.laneResults.count == 1)
        #expect(result.payload.blockedLanes.isEmpty)
        #expect(result.payload.failedLanes.isEmpty)
    }

    @Test("an external oracle lane blocks until an oracle result exists")
    func missingOracleResultBlocks() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-oracle-missing")
        defer { Self.removeTemporaryRoot(root) }

        let request = try Self.makeRequest(root: root, laneKind: .externalOracle)
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.qualified == false)
        #expect(result.payload.blockedLanes == ["drc:external-oracle"])
        #expect(result.diagnostics.contains { $0.code == "QUALIFICATION_ORACLE_RESULT_MISSING" })
    }

    @Test("stale retained evidence is fail-closed")
    func staleEvidenceBlocks() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-stale")
        defer { Self.removeTemporaryRoot(root) }

        var request = try Self.makeRequest(root: root, laneKind: .nativeCorpus)
        request.policy.maximumEvidenceAgeSeconds = 60
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.qualified == false)
        #expect(result.diagnostics.contains { $0.code == "QUALIFICATION_EVIDENCE_STALE" })
    }

    @Test("a tampered role artifact cannot be hidden by a stale inputs list")
    func tamperedRoleArtifactBlocks() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-tampered")
        defer { Self.removeTemporaryRoot(root) }

        var request = try Self.makeRequest(root: root, laneKind: .nativeCorpus)
        request.qualificationReportArtifact.sha256 = String(repeating: "f", count: 64)
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.qualified == false)
        #expect(result.diagnostics.contains { $0.code == "QUALIFICATION_ARTIFACT_INTEGRITY_FAILED" })
    }

    @Test("an incomplete process scope blocks qualification")
    func incompleteProcessScopeBlocks() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-scope-missing")
        defer { Self.removeTemporaryRoot(root) }

        var request = try Self.makeRequest(root: root, laneKind: .nativeCorpus)
        request.policy.requiredQualificationScope.implementationID = ""
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.qualified == false)
        #expect(result.diagnostics.contains { $0.code == "INVALID_QUALIFICATION_POLICY" })
    }

    @Test("weak retained metrics fail the qualification lane")
    func weakMetricsFailLane() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-weak-metrics")
        defer { Self.removeTemporaryRoot(root) }

        let request = try Self.makeRequest(root: root, laneKind: .nativeCorpus, weakMetrics: true)
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .failed)
        #expect(result.payload.qualified == false)
        #expect(result.payload.failedLanes == ["drc:native-corpus"])
        #expect(result.diagnostics.contains { $0.code == "QUALIFICATION_METRIC_FAILED" })
    }

    @Test("a report identity mismatch blocks retained qualification")
    func reportIdentityMismatchBlocks() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-report-identity")
        defer { Self.removeTemporaryRoot(root) }

        let request = try Self.makeRequest(root: root, laneKind: .nativeCorpus, mismatchedReportIdentity: true)
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.qualified == false)
        #expect(result.diagnostics.contains { $0.code == "QUALIFICATION_REPORT_IDENTITY_MISMATCH" })
    }

    private static func makeRequest(
        root: URL,
        laneKind: ReleaseQualificationLaneKind,
        weakMetrics: Bool = false,
        mismatchedReportIdentity: Bool = false
    ) throws -> ReleaseQualificationRequest {
        let scope = ToolQualificationScope(
            implementationID: "native-drc",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "native-drc-v1",
            processProfileID: "sky130",
            deckDigest: String(repeating: "b", count: 64)
        )
        let laneID = "drc:" + laneKind.rawValue
        let lane = ReleaseQualificationLane(
            laneID: laneID,
            domain: "drc",
            kind: laneKind,
            corpusSpecPath: "qualification/suite.json",
            reportPath: "reports/drc.json",
            evidenceExportPath: "evidence/drc.json",
            oracleBackendID: laneKind == .externalOracle ? "magic" : nil
        )
        let suite = RetainedCorpusSuite(
            suiteID: "sky130-retained-smoke",
            lanes: [lane],
            createdAt: Self.timestamp(Self.evaluationDate.addingTimeInterval(-900)),
            sourceDashboardPath: "qualification/dashboard.json",
            requirements: RetainedCorpusSuite.Requirements(
                domainIDs: ["drc"],
                requireExternalOracles: laneKind == .externalOracle,
                requiredArtifacts: ["reports/drc.json", "evidence/drc.json"]
            )
        )
        let reportData = Data("domain-report".utf8)
        let reportArtifact = try Self.makeArtifact(
            root: root,
            relativePath: "reports/drc.json",
            data: reportData,
            kind: .report,
            format: .json
        )
        let evidenceData = Data("tool-evidence".utf8)
        let evidenceArtifact = try Self.makeArtifact(
            root: root,
            relativePath: "evidence/drc.json",
            data: evidenceData,
            kind: .report,
            format: .json
        )
        let report = RetainedCorpusReport(
            status: "passed",
            createdAt: Self.timestamp(Self.evaluationDate.addingTimeInterval(-900)),
            domainResults: [
                RetainedCorpusReport.DomainResult(
                    domain: "drc",
                    status: "passed",
                    qualified: !weakMetrics,
                    caseCount: weakMetrics ? 0 : 3,
                    coverageTagCount: weakMetrics ? 0 : 4,
                    coveredRequiredCoverageTagCount: weakMetrics ? 0 : 4,
                    passRate: weakMetrics ? 0.5 : 1,
                    oracleAgreementRate: nil,
                    durationBudgetPassRate: weakMetrics ? 0.5 : 1,
                    report: RetainedCorpusReport.ArtifactIdentity(
                        path: reportArtifact.path,
                        sha256: mismatchedReportIdentity ? String(repeating: "f", count: 64) : reportArtifact.sha256,
                        byteCount: reportArtifact.byteCount,
                        status: "passed"
                    ),
                    toolEvidence: RetainedCorpusReport.ToolEvidenceObservation(
                        evidenceID: "corpus-drc",
                        checkedAt: Self.timestamp(Self.evaluationDate.addingTimeInterval(-900))
                    ),
                    toolEvidenceExport: RetainedCorpusReport.ArtifactIdentity(
                        path: evidenceArtifact.path,
                        sha256: evidenceArtifact.sha256,
                        byteCount: evidenceArtifact.byteCount,
                        status: "passed"
                    )
                )
            ]
        )
        let suiteArtifact = try Self.makeJSONArtifact(
            root: root,
            relativePath: "qualification/suite.json",
            value: suite,
            kind: .report
        )
        let reportArtifactReference = try Self.makeJSONArtifact(
            root: root,
            relativePath: "qualification/report.json",
            value: report,
            kind: .report
        )
        let policy = ReleaseQualificationPolicy(
            policyID: "sky130-retained-corpus",
            processProfileID: "sky130",
            requiredLanes: [lane],
            requiredQualificationLevel: .corpusChecked,
            requiredQualificationScope: scope,
            minimumCaseCount: 1,
            minimumCoverageTagCount: 1,
            minimumCoveredRequiredCoverageTagCount: 1,
            minimumPassRate: 1,
            minimumOracleAgreementRate: 1,
            minimumDurationBudgetPassRate: 1,
            maximumEvidenceAgeSeconds: 3_600
        )
        let toolEvidence = ToolEvidence(
            evidenceID: "corpus-drc",
            kind: .corpus,
            artifact: evidenceArtifact,
            qualification: ToolEvidenceQualificationSummary(
                qualified: true,
                policyID: policy.policyID,
                observedMetrics: ["passRate": 1],
                observedCounts: ["caseCount": 3],
                scope: scope
            ),
            checkedAt: Self.evaluationDate.addingTimeInterval(-900)
        )
        return ReleaseQualificationRequest(
            runID: "qualification-(laneKind.rawValue)",
            projectRoot: root.path,
            processProfileID: "sky130",
            suiteArtifact: suiteArtifact,
            qualificationReportArtifact: reportArtifactReference,
            domainReportArtifacts: [reportArtifact],
            evidenceArtifacts: [evidenceArtifact],
            toolEvidence: [toolEvidence],
            policy: policy
        )
    }

    private static func makeJSONArtifact<Value: Encodable>(
        root: URL,
        relativePath: String,
        value: Value,
        kind: XcircuiteFileKind
    ) throws -> XcircuiteFileReference {
        try makeArtifact(
            root: root,
            relativePath: relativePath,
            data: try encode(value),
            kind: kind,
            format: .json
        )
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func makeArtifact(
        root: URL,
        relativePath: String,
        data: Data,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return XcircuiteFileReference(
            artifactID: relativePath.replacingOccurrences(of: "/", with: "-"),
            path: relativePath,
            kind: kind,
            format: format,
            sha256: XcircuiteHasher().sha256(data: data),
            byteCount: Int64(data.count)
        )
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func makeTemporaryRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "release-engine-" + name + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
