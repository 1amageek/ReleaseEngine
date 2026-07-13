import Foundation
import QualificationEngine
import Testing
import ToolQualification
import CircuiteFoundation

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
        #expect(result.diagnostics.contains { $0.code.rawValue == "QUALIFICATION_ORACLE_RESULT_MISSING" })
    }

    @Test("native and external oracle cases must correlate before oracle promotion")
    func correlatedOracleCasesPromoteToOracleChecked() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-oracle-correlated")
        defer { Self.removeTemporaryRoot(root) }

        let request = try Self.makeCorrelatedOracleRequest(root: root)
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.qualified)
        #expect(result.payload.qualificationLevel == .oracleChecked)
        #expect(result.payload.promotionStatus == .oracleChecked)
        #expect(result.payload.blockedLanes.isEmpty)
        #expect(result.payload.failedLanes.isEmpty)
    }

    @Test("oracle case disagreement fails instead of inferring agreement from aggregate pass rate")
    func oracleCaseDisagreementFailsClosed() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-oracle-mismatch")
        defer { Self.removeTemporaryRoot(root) }

        let request = try Self.makeCorrelatedOracleRequest(root: root, agreement: false)
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .failed)
        #expect(result.payload.qualified == false)
        #expect(result.payload.failedLanes == ["drc:external-oracle"])
        #expect(result.payload.laneResults.first?.failureCodes.contains("ORACLE_CASE_MISMATCH") == true)
        #expect(result.diagnostics.contains { $0.code.rawValue == "QUALIFICATION_METRIC_FAILED" })
    }

    @Test("oracle case set mismatch blocks correlation")
    func oracleCaseSetMismatchBlocks() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-oracle-case-set")
        defer { Self.removeTemporaryRoot(root) }

        let request = try Self.makeCorrelatedOracleRequest(root: root, oracleCaseIDs: ["case-1"])
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.qualified == false)
        #expect(result.payload.blockedLanes == ["drc:external-oracle"])
        #expect(result.diagnostics.contains { $0.code.rawValue == "QUALIFICATION_ORACLE_CASE_SET_MISMATCH" })
    }

    @Test("production eligibility requires a fresh scoped production approval")
    func productionApprovalPromotesScopedQualification() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-production-promotion")
        defer { Self.removeTemporaryRoot(root) }

        let request = try Self.makeCorrelatedOracleRequest(
            root: root,
            requiredLevel: .productionEligible
        )
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.qualified)
        #expect(result.payload.qualificationLevel == .productionEligible)
        #expect(result.payload.promotionStatus == .productionEligible)
    }

    @Test("independent process qualification artifact is required for PDK release eligibility")
    func independentProcessQualificationArtifactPromotesReleaseEligibility() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-independent-process")
        defer { Self.removeTemporaryRoot(root) }

        var request = try Self.makeCorrelatedOracleRequest(root: root, requiredLevel: .productionEligible)
        let baseScope = request.policy.requiredQualificationScope
        let scope = ToolQualificationScope(
            implementationID: baseScope.implementationID,
            binaryDigest: baseScope.binaryDigest,
            algorithmVersion: baseScope.algorithmVersion,
            processProfileID: baseScope.processProfileID,
            deckDigest: baseScope.deckDigest,
            pdkID: "sky130-openlane",
            pdkDigest: String(repeating: "c", count: 64)
        )
        request.policy.requiredQualificationScope = scope
        request.policy.requireIndependentProcessQualification = true
        request.toolEvidence = request.toolEvidence.map { item in
            var item = item
            item.qualification?.scope = scope
            return item
        }

        let qualificationID = "qualification-sky130-openlane-drc"
        let record = ToolProcessQualificationEvidence(
            qualificationID: qualificationID,
            toolID: "native-drc",
            scope: scope,
            status: .qualified,
            corpusEvidenceIDs: ["corpus-drc"],
            oracleEvidenceIDs: ["oracle-magic-drc"],
            healthEvidenceIDs: ["health-native-drc"],
            approvalEvidenceIDs: ["approval-human-sky130"],
            evidenceArtifactIDs: ["evidence-process-qualification"],
            independenceVerified: true,
            qualifiedAt: Self.evaluationDate.addingTimeInterval(-900),
            expiresAt: Self.evaluationDate.addingTimeInterval(3_600)
        )
        let recordReference = try Self.makeProcessQualificationArtifact(
            root: root,
            relativePath: "evidence/process-qualification.json",
            value: record
        )
        request.evidenceArtifacts.append(recordReference)
        if let index = request.toolEvidence.firstIndex(where: { $0.kind == .productionApproval }) {
            request.toolEvidence[index].artifact = recordReference
            request.toolEvidence[index].qualification = ToolEvidenceQualificationSummary(
                qualified: true,
                policyID: request.policy.policyID,
                observedCounts: ["approvalCount": 1],
                scope: scope,
                qualificationID: qualificationID,
                independenceVerified: true
            )
        }

        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .completed)
        #expect(result.payload.qualified)
        #expect(result.payload.qualificationLevel == .productionEligible)
        #expect(result.payload.promotionStatus == .productionEligible)
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
        #expect(result.diagnostics.contains { $0.code.rawValue == "QUALIFICATION_EVIDENCE_STALE" })
    }

    @Test("a tampered role artifact cannot be hidden by a stale inputs list")
    func tamperedRoleArtifactBlocks() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-tampered")
        defer { Self.removeTemporaryRoot(root) }

        var request = try Self.makeRequest(root: root, laneKind: .nativeCorpus)
        let originalArtifact = request.qualificationReportArtifact
        request.qualificationReportArtifact = ArtifactReference(
            id: originalArtifact.id,
            locator: originalArtifact.locator,
            digest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "f", count: 64)
            ),
            byteCount: originalArtifact.byteCount
        )
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.qualified == false)
        #expect(result.diagnostics.contains { $0.code.rawValue == "QUALIFICATION_ARTIFACT_INTEGRITY_FAILED" })
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
        #expect(result.diagnostics.contains { $0.code.rawValue == "INVALID_QUALIFICATION_POLICY" })
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
        #expect(result.diagnostics.contains { $0.code.rawValue == "QUALIFICATION_METRIC_FAILED" })
    }

    @Test("a report identity mismatch blocks retained qualification")
    func reportIdentityMismatchBlocks() async throws {
        let root = try Self.makeTemporaryRoot(named: "qualification-report-identity")
        defer { Self.removeTemporaryRoot(root) }

        let request = try Self.makeRequest(root: root, laneKind: .nativeCorpus, mismatchedReportIdentity: true)
        let result = try await DefaultRetainedQualificationEvaluator(now: { Self.evaluationDate }).execute(request)

        #expect(result.status == .blocked)
        #expect(result.payload.qualified == false)
        #expect(result.diagnostics.contains { $0.code.rawValue == "QUALIFICATION_REPORT_IDENTITY_MISMATCH" })
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
            oracleBackendID: laneKind == .externalOracle ? "magic" : nil,
            requiredProbeIDs: laneKind == .externalOracle ? ["probe:drc"] : []
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
                        byteCount: Int64(reportArtifact.byteCount),
                        status: "passed"
                    ),
                    toolEvidence: RetainedCorpusReport.ToolEvidenceObservation(
                        evidenceID: "corpus-drc",
                        checkedAt: Self.timestamp(Self.evaluationDate.addingTimeInterval(-900))
                    ),
                    toolEvidenceExport: RetainedCorpusReport.ArtifactIdentity(
                        path: evidenceArtifact.path,
                        sha256: evidenceArtifact.sha256,
                        byteCount: Int64(evidenceArtifact.byteCount),
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
            runID: "qualification-\(laneKind.rawValue)",
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

    private static func makeCorrelatedOracleRequest(
        root: URL,
        requiredLevel: ToolQualificationLevel = .oracleChecked,
        agreement: Bool = true,
        oracleCaseIDs: Set<String> = ["case-1", "case-2"]
    ) throws -> ReleaseQualificationRequest {
        let scope = ToolQualificationScope(
            implementationID: "native-drc",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "native-drc-v1",
            processProfileID: "sky130",
            deckDigest: String(repeating: "b", count: 64)
        )
        let nativeLane = ReleaseQualificationLane(
            laneID: "drc:native-corpus",
            domain: "drc",
            kind: .nativeCorpus,
            reportPath: "reports/drc-native.json",
            evidenceExportPath: "evidence/drc.json"
        )
        let oracleLane = ReleaseQualificationLane(
            laneID: "drc:external-oracle",
            domain: "drc",
            kind: .externalOracle,
            corpusSpecPath: "qualification/corpus-spec.json",
            reportPath: "reports/drc-oracle.json",
            evidenceExportPath: "evidence/drc.json",
            oracleBackendID: "magic",
            requiredProbeIDs: ["probe:drc"]
        )
        let suiteCases = [
            RetainedCorpusCase(
                caseID: "case-1",
                domain: "drc",
                coverageTags: ["spacing"],
                probeIDs: ["probe:drc"]
            ),
            RetainedCorpusCase(
                caseID: "case-2",
                domain: "drc",
                coverageTags: ["enclosure"],
                probeIDs: ["probe:drc"]
            ),
        ]
        let suite = RetainedCorpusSuite(
            suiteID: "sky130-retained-oracle",
            lanes: [nativeLane, oracleLane],
            cases: suiteCases,
            createdAt: Self.timestamp(Self.evaluationDate.addingTimeInterval(-900)),
            requirements: RetainedCorpusSuite.Requirements(
                domainIDs: ["drc"],
                requireExternalOracles: true,
                requiredArtifacts: ["qualification/corpus-spec.json", "reports/drc-native.json", "reports/drc-oracle.json"]
            )
        )
        let nativeReportReference = try Self.makeArtifact(
            root: root,
            relativePath: "reports/drc-native.json",
            data: Data("native-report".utf8),
            kind: .report,
            format: .json
        )
        let oracleReportReference = try Self.makeArtifact(
            root: root,
            relativePath: "reports/drc-oracle.json",
            data: Data("oracle-report".utf8),
            kind: .report,
            format: .json
        )
        let evidenceReference = try Self.makeArtifact(
            root: root,
            relativePath: "evidence/drc.json",
            data: Data("oracle-evidence".utf8),
            kind: .report,
            format: .json
        )
        let corpusSpecReference = try Self.makeArtifact(
            root: root,
            relativePath: "qualification/corpus-spec.json",
            data: Data("corpus-spec".utf8),
            kind: .report,
            format: .json
        )
        let nativeCaseResults = suiteCases.map {
            RetainedCorpusCaseResult(
                caseID: $0.caseID,
                domain: $0.domain,
                status: "passed",
                qualified: true,
                coverageTags: $0.coverageTags,
                probeIDs: $0.probeIDs
            )
        }
        let oracleCaseResults = suiteCases.filter { oracleCaseIDs.contains($0.caseID) }.map {
            RetainedOracleCaseResult(
                caseID: $0.caseID,
                domain: $0.domain,
                nativeStatus: "passed",
                oracleStatus: agreement ? "passed" : ($0.caseID == "case-2" ? "failed" : "passed"),
                agreement: agreement ? true : ($0.caseID == "case-2" ? false : true),
                coverageTags: $0.coverageTags,
                probeIDs: $0.probeIDs
            )
        }
        let report = RetainedCorpusReport(
            status: agreement ? "passed" : "failed",
            createdAt: Self.timestamp(Self.evaluationDate.addingTimeInterval(-900)),
            domainResults: [
                RetainedCorpusReport.DomainResult(
                    domain: "drc",
                    status: "passed",
                    qualified: true,
                    caseCount: 2,
                    coverageTagCount: 2,
                    coveredRequiredCoverageTagCount: 2,
                    passRate: 1,
                    oracleAgreementRate: nil,
                    durationBudgetPassRate: 1,
                    report: RetainedCorpusReport.ArtifactIdentity(
                        path: nativeReportReference.path,
                        sha256: nativeReportReference.sha256,
                        byteCount: Int64(nativeReportReference.byteCount),
                        status: "passed"
                    ),
                    toolEvidence: nil,
                    toolEvidenceExport: RetainedCorpusReport.ArtifactIdentity(
                        path: evidenceReference.path,
                        sha256: evidenceReference.sha256,
                        byteCount: Int64(evidenceReference.byteCount),
                        status: "passed"
                    ),
                    caseResults: nativeCaseResults
                ),
            ],
            externalOracleResults: [
                RetainedCorpusReport.ExternalOracleResult(
                    domain: "drc",
                    oracleBackendID: "magic",
                    status: agreement ? "passed" : "failed",
                    qualified: agreement,
                    caseCount: oracleCaseResults.count,
                    coverageTagCount: 2,
                    coveredRequiredCoverageTagCount: 2,
                    passRate: agreement ? 1 : 0.5,
                    oracleAgreementRate: agreement ? 1 : 0.5,
                    durationBudgetPassRate: 1,
                    report: RetainedCorpusReport.ArtifactIdentity(
                        path: oracleReportReference.path,
                        sha256: oracleReportReference.sha256,
                        byteCount: Int64(oracleReportReference.byteCount),
                        status: "passed"
                    ),
                    toolEvidence: nil,
                    toolEvidenceExport: RetainedCorpusReport.ArtifactIdentity(
                        path: evidenceReference.path,
                        sha256: evidenceReference.sha256,
                        byteCount: Int64(evidenceReference.byteCount),
                        status: "passed"
                    ),
                    caseResults: oracleCaseResults
                ),
            ]
        )
        let suiteReference = try Self.makeJSONArtifact(
            root: root,
            relativePath: "qualification/suite.json",
            value: suite,
            kind: .report
        )
        let reportReference = try Self.makeJSONArtifact(
            root: root,
            relativePath: "qualification/report.json",
            value: report,
            kind: .report
        )
        var requiredEvidenceKinds: [ToolEvidenceKind] = [.corpus, .oracle]
        if requiredLevel == .productionEligible {
            requiredEvidenceKinds.append(.productionApproval)
        }
        let policy = ReleaseQualificationPolicy(
            policyID: "sky130-retained-oracle",
            processProfileID: "sky130",
            requiredLanes: [nativeLane, oracleLane],
            requiredEvidenceKinds: requiredEvidenceKinds,
            requiredQualifiedEvidenceKinds: requiredEvidenceKinds,
            requiredQualificationLevel: requiredLevel,
            requiredQualificationScope: scope,
            minimumCaseCount: 1,
            minimumCoverageTagCount: 1,
            minimumCoveredRequiredCoverageTagCount: 1,
            minimumPassRate: 1,
            minimumOracleAgreementRate: 1,
            minimumDurationBudgetPassRate: 1,
            maximumEvidenceAgeSeconds: 3_600
        )
        var toolEvidence = [
            ToolEvidence(
                evidenceID: "corpus-drc",
                kind: .corpus,
                artifact: evidenceReference,
                qualification: ToolEvidenceQualificationSummary(
                    qualified: true,
                    policyID: policy.policyID,
                    observedMetrics: ["passRate": 1],
                    observedCounts: ["caseCount": 2],
                    scope: scope
                ),
                checkedAt: Self.evaluationDate.addingTimeInterval(-900)
            ),
            ToolEvidence(
                evidenceID: "oracle-magic-drc",
                kind: .oracle,
                artifact: oracleReportReference,
                qualification: ToolEvidenceQualificationSummary(
                    qualified: agreement,
                    policyID: policy.policyID,
                    observedMetrics: ["agreementRate": agreement ? 1 : 0.5],
                    observedCounts: ["caseCount": oracleCaseResults.count],
                    failureCodes: agreement ? [] : ["ORACLE_CASE_MISMATCH"],
                    scope: scope
                ),
                checkedAt: Self.evaluationDate.addingTimeInterval(-900)
            ),
        ]
        if requiredLevel == .productionEligible {
            toolEvidence.append(
                ToolEvidence(
                    evidenceID: "production-approval-sky130",
                    kind: .productionApproval,
                    artifact: reportReference,
                    qualification: ToolEvidenceQualificationSummary(
                        qualified: true,
                        policyID: policy.policyID,
                        observedCounts: ["approvalCount": 1],
                        scope: scope
                    ),
                    checkedAt: Self.evaluationDate.addingTimeInterval(-900)
                )
            )
        }
        return ReleaseQualificationRequest(
            runID: "qualification-external-oracle",
            projectRoot: root.path,
            processProfileID: "sky130",
            suiteArtifact: suiteReference,
            qualificationReportArtifact: reportReference,
            corpusSpecArtifacts: [corpusSpecReference],
            domainReportArtifacts: [nativeReportReference, oracleReportReference],
            evidenceArtifacts: [evidenceReference],
            toolEvidence: toolEvidence,
            policy: policy
        )
    }

    private static func makeJSONArtifact<Value: Encodable>(
        root: URL,
        relativePath: String,
        value: Value,
        kind: ArtifactKind
    ) throws -> ArtifactReference {
        try makeArtifact(
            root: root,
            relativePath: relativePath,
            data: try encode(value),
            kind: kind,
            format: .json
        )
    }

    private static func makeProcessQualificationArtifact<Value: Encodable>(
        root: URL,
        relativePath: String,
        value: Value
    ) throws -> ArtifactReference {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try makeArtifact(
            root: root,
            relativePath: relativePath,
            data: try encoder.encode(value),
            kind: .report,
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
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return makeTestArtifactReference(
            artifactID: relativePath.replacingOccurrences(of: "/", with: "-"),
            path: relativePath,
            kind: kind,
            format: format,
            sha256: SHA256ContentDigester().sha256(data: data),
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
