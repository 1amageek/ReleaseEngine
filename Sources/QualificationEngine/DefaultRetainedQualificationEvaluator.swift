import Foundation
import ReleaseCore
import ToolQualification
import XcircuitePackage

public struct DefaultRetainedQualificationEvaluator: ReleaseQualificationEvaluating {
    private let verifier: XcircuiteFileReferenceVerifier
    private let now: @Sendable () -> Date

    public init(
        verifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.verifier = verifier
        self.now = now
    }

    public func execute(
        _ request: ReleaseQualificationRequest
    ) async throws -> XcircuiteEngineResultEnvelope<ReleaseQualificationPayload> {
        let startedAt = now()
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "release.qualification",
            implementationID: "native.release.qualification",
            implementationVersion: "1.0.0",
            startedAt: startedAt,
            completedAt: now()
        )

        guard request.schemaVersion == ReleaseQualificationRequest.currentSchemaVersion else {
            return blockedEnvelope(request: request, metadata: metadata, code: "INVALID_QUALIFICATION_REQUEST_SCHEMA", message: "Unsupported qualification request schema version.")
        }
        guard !request.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return blockedEnvelope(request: request, metadata: metadata, code: "RUN_ID_REQUIRED", message: "Qualification run ID must not be empty.")
        }
        guard request.policy.isValid else {
            return blockedEnvelope(request: request, metadata: metadata, code: "INVALID_QUALIFICATION_POLICY", message: "Qualification policy is incomplete, inconsistent, or outside the supported metric range.")
        }
        guard request.processProfileID == request.policy.processProfileID else {
            return blockedEnvelope(request: request, metadata: metadata, code: "PROCESS_PROFILE_MISMATCH", message: "Qualification request and policy refer to different process profiles.")
        }
        guard let projectRoot = request.projectRoot.map(URL.init(fileURLWithPath:)) else {
            return blockedEnvelope(request: request, metadata: metadata, code: "QUALIFICATION_PROJECT_ROOT_REQUIRED", message: "A project root is required to verify retained qualification artifacts.")
        }
        var diagnostics: [XcircuiteEngineDiagnostic] = []
        var blockedLanes = Set<String>()
        var failedLanes = Set<String>()
        var laneResults: [ReleaseQualificationDomainResult] = []
        var status: XcircuiteEngineExecutionStatus = .completed

        func add(_ code: String, _ message: String, entity: String?, blocked: Bool) {
            diagnostics.append(XcircuiteEngineDiagnostic(
                severity: .error,
                code: code,
                message: message,
                entity: entity,
                suggestedActions: ["inspect_retained_qualification_artifacts", "rerun_qualification_workflow"]
            ))
            if blocked {
                status = .blocked
            } else if status != .blocked {
                status = .failed
            }
        }

        let artifacts = requestArtifacts(request)
        for artifact in artifacts {
            let integrity = verifier.verify(artifact, projectRoot: projectRoot)
            if integrity.status != .verified {
                add("QUALIFICATION_ARTIFACT_INTEGRITY_FAILED", integrity.message, entity: artifact.path, blocked: true)
            }
        }
        guard status != .blocked else {
            return envelope(
                request: request,
                status: status,
                diagnostics: diagnostics,
                artifacts: artifacts,
                metadata: metadata,
                payload: payload(request: request, status: status, level: .unknown, digest: nil, diagnostics: diagnostics, laneResults: laneResults, blockedLanes: blockedLanes, failedLanes: failedLanes)
            )
        }

        guard let suiteURL = verifier.resolvedURL(for: request.suiteArtifact, projectRoot: projectRoot),
              let reportURL = verifier.resolvedURL(for: request.qualificationReportArtifact, projectRoot: projectRoot) else {
            return blockedEnvelope(request: request, metadata: metadata, code: "QUALIFICATION_ARTIFACT_PATH_INVALID", message: "Retained suite or report path is not a safe project-relative path.")
        }

        let suite: RetainedCorpusSuite
        let report: RetainedCorpusReport
        do {
            let suiteData = try Data(contentsOf: suiteURL)
            suite = try JSONDecoder().decode(RetainedCorpusSuite.self, from: suiteData)
            let reportData = try Data(contentsOf: reportURL)
            report = try JSONDecoder().decode(RetainedCorpusReport.self, from: reportData)
        } catch {
            return blockedEnvelope(request: request, metadata: metadata, code: "QUALIFICATION_REPORT_PARSE_FAILED", message: "Retained suite or report could not be decoded: \(error.localizedDescription)")
        }

        guard suite.schemaVersion == RetainedCorpusSuite.currentSchemaVersion,
              report.schemaVersion == RetainedCorpusReport.currentSchemaVersion else {
            return blockedEnvelope(request: request, metadata: metadata, code: "QUALIFICATION_ARTIFACT_SCHEMA_MISMATCH", message: "Retained suite and report schema versions are not supported.")
        }
        guard suite.isValid, report.isValid else {
            return blockedEnvelope(request: request, metadata: metadata, code: "QUALIFICATION_ARTIFACT_CONTRACT_INVALID", message: "Retained suite or report contains duplicate, empty, or malformed lane identities.")
        }
        validateFreshness(
            reportCreatedAt: report.createdAt,
            maximumAgeSeconds: request.policy.maximumEvidenceAgeSeconds,
            currentDate: now(),
            add: add
        )
        validateToolEvidence(
            request.toolEvidence,
            evidenceArtifacts: request.evidenceArtifacts,
            policy: request.policy,
            projectRoot: projectRoot,
            currentDate: now(),
            add: add
        )

        for requiredLane in request.policy.requiredLanes.sorted(by: { $0.laneID < $1.laneID }) {
            guard let suiteLane = suite.lanes.first(where: { $0.laneID == requiredLane.laneID }) else {
                blockedLanes.insert(requiredLane.laneID)
                add("QUALIFICATION_LANE_MISSING", "Required qualification lane is missing from the retained suite.", entity: requiredLane.laneID, blocked: true)
                continue
            }
            guard suiteLane.domain == requiredLane.domain, suiteLane.kind == requiredLane.kind else {
                blockedLanes.insert(requiredLane.laneID)
                add("QUALIFICATION_LANE_MISMATCH", "Retained suite lane domain or kind does not match the qualification policy.", entity: requiredLane.laneID, blocked: true)
                continue
            }

            let reportArtifact = matchingArtifact(for: requiredLane.reportPath, in: request.domainReportArtifacts)
            if requiredLane.reportPath != nil && reportArtifact == nil {
                blockedLanes.insert(requiredLane.laneID)
                add("QUALIFICATION_DOMAIN_REPORT_MISSING", "Required domain report artifact is not present in the request.", entity: requiredLane.laneID, blocked: true)
            }
            let corpusArtifact = matchingArtifact(for: requiredLane.corpusSpecPath, in: request.corpusSpecArtifacts)
            if requiredLane.kind == .externalOracle,
               requiredLane.corpusSpecPath != nil && corpusArtifact == nil {
                blockedLanes.insert(requiredLane.laneID)
                add("QUALIFICATION_CORPUS_SPEC_MISSING", "Required corpus specification artifact is not present in the request.", entity: requiredLane.laneID, blocked: true)
            }
            let evidenceArtifact = matchingArtifact(for: requiredLane.evidenceExportPath, in: request.evidenceArtifacts)
            if requiredLane.evidenceExportPath != nil && evidenceArtifact == nil {
                blockedLanes.insert(requiredLane.laneID)
                add("QUALIFICATION_TOOL_EVIDENCE_MISSING", "Required tool evidence export artifact is not present in the request.", entity: requiredLane.laneID, blocked: true)
            }

            let observation: Observation
            switch requiredLane.kind {
            case .nativeCorpus:
                guard let domainResult = report.domainResults.first(where: { $0.domain == requiredLane.domain }) else {
                    blockedLanes.insert(requiredLane.laneID)
                    add("QUALIFICATION_DOMAIN_RESULT_MISSING", "Retained report has no result for the required native corpus domain.", entity: requiredLane.laneID, blocked: true)
                    continue
                }
                observation = .domain(domainResult)
            case .externalOracle:
                guard let oracleResult = report.externalOracleResults.first(where: {
                    $0.domain == requiredLane.domain
                        && $0.oracleBackendID == requiredLane.oracleBackendID
                }) else {
                    blockedLanes.insert(requiredLane.laneID)
                    add("QUALIFICATION_ORACLE_RESULT_MISSING", "Retained report has no result for the required external oracle lane.", entity: requiredLane.laneID, blocked: true)
                    continue
                }
                observation = .oracle(oracleResult)
            }

            if requiredLane.reportPath != nil,
               let reportArtifact,
               !identityMatches(observation.reportIdentity, reference: reportArtifact) {
                blockedLanes.insert(requiredLane.laneID)
                add("QUALIFICATION_REPORT_IDENTITY_MISMATCH", "Retained report identity does not match the verified report artifact reference.", entity: requiredLane.laneID, blocked: true)
            }
            if requiredLane.evidenceExportPath != nil,
               let evidenceArtifact,
               !identityMatches(observation.evidenceIdentity, reference: evidenceArtifact) {
                blockedLanes.insert(requiredLane.laneID)
                add("QUALIFICATION_EVIDENCE_IDENTITY_MISMATCH", "Retained tool-evidence identity does not match the verified evidence artifact reference.", entity: requiredLane.laneID, blocked: true)
            }

            var failureCodes: [String] = []
            let metrics = observation.metrics
            if observation.status != "passed" || !observation.qualified { failureCodes.append("RESULT_NOT_QUALIFIED") }
            if metrics.caseCount ?? 0 < request.policy.minimumCaseCount { failureCodes.append("CASE_COUNT_BELOW_THRESHOLD") }
            if metrics.coverageTagCount ?? 0 < request.policy.minimumCoverageTagCount { failureCodes.append("COVERAGE_BELOW_THRESHOLD") }
            if metrics.coveredRequiredCoverageTagCount ?? 0 < request.policy.minimumCoveredRequiredCoverageTagCount { failureCodes.append("REQUIRED_COVERAGE_BELOW_THRESHOLD") }
            if (metrics.passRate ?? -1) < request.policy.minimumPassRate { failureCodes.append("PASS_RATE_BELOW_THRESHOLD") }
            if (metrics.durationBudgetPassRate ?? -1) < request.policy.minimumDurationBudgetPassRate { failureCodes.append("DURATION_BUDGET_BELOW_THRESHOLD") }
            if requiredLane.kind == .externalOracle {
                if observation.status == "unavailable" {
                    blockedLanes.insert(requiredLane.laneID)
                    add("QUALIFICATION_ORACLE_UNAVAILABLE", "The required external oracle reported an unavailable state.", entity: requiredLane.laneID, blocked: true)
                }
                guard let oracleAgreementRate = metrics.oracleAgreementRate else {
                    blockedLanes.insert(requiredLane.laneID)
                    add("QUALIFICATION_ORACLE_AGREEMENT_MISSING", "External oracle lane has no oracle agreement metric.", entity: requiredLane.laneID, blocked: true)
                    continue
                }
                if oracleAgreementRate < request.policy.minimumOracleAgreementRate { failureCodes.append("ORACLE_AGREEMENT_BELOW_THRESHOLD") }
                let correlation = validateOracleCorrelation(
                    requiredLane: requiredLane,
                    suite: suite,
                    report: report
                )
                if correlation.blocked {
                    blockedLanes.insert(requiredLane.laneID)
                    for diagnostic in correlation.diagnostics {
                        add(diagnostic.code, diagnostic.message, entity: requiredLane.laneID, blocked: true)
                    }
                }
                failureCodes.append(contentsOf: correlation.failureCodes)
            }

            let domainStatus = failureCodes.isEmpty ? "passed" : "failed"
            if !failureCodes.isEmpty {
                failedLanes.insert(requiredLane.laneID)
                add("QUALIFICATION_METRIC_FAILED", "Retained qualification metrics do not satisfy the policy thresholds: \(failureCodes.joined(separator: ", ")).", entity: requiredLane.laneID, blocked: false)
            }
            laneResults.append(ReleaseQualificationDomainResult(
                laneID: requiredLane.laneID,
                domain: requiredLane.domain,
                kind: requiredLane.kind,
                status: domainStatus,
                qualified: failureCodes.isEmpty,
                caseCount: metrics.caseCount,
                coverageTagCount: metrics.coverageTagCount,
                coveredRequiredCoverageTagCount: metrics.coveredRequiredCoverageTagCount,
                passRate: metrics.passRate,
                oracleAgreementRate: metrics.oracleAgreementRate,
                durationBudgetPassRate: metrics.durationBudgetPassRate,
                failureCodes: failureCodes,
                corpusArtifact: corpusArtifact,
                reportArtifact: reportArtifact,
                evidenceArtifact: evidenceArtifact
            ))
        }

        var level: ToolQualificationLevel = request.policy.requiredLanes.contains { $0.kind == .externalOracle } ? .oracleChecked : .corpusChecked
        let allLanesQualified = laneResults.count == request.policy.requiredLanes.count
            && blockedLanes.isEmpty
            && failedLanes.isEmpty
            && status == .completed
        if allLanesQualified && request.policy.requiredQualificationLevel == .productionEligible {
            level = .productionEligible
        }
        if level < request.policy.requiredQualificationLevel {
            add("QUALIFICATION_LEVEL_BELOW_POLICY", "Observed retained evidence level is below the policy requirement.", entity: request.policy.policyID, blocked: true)
        }
        let qualificationDigest = makeQualificationDigest(request: request, laneResults: laneResults)
        return envelope(
            request: request,
            status: status,
            diagnostics: diagnostics,
            artifacts: artifacts,
            metadata: metadata,
            payload: payload(request: request, status: status, level: level, digest: qualificationDigest, diagnostics: diagnostics, laneResults: laneResults, blockedLanes: blockedLanes, failedLanes: failedLanes)
        )
    }

    private enum Observation {
        case domain(RetainedCorpusReport.DomainResult)
        case oracle(RetainedCorpusReport.ExternalOracleResult)

        var status: String? {
            switch self {
            case .domain(let value): value.status
            case .oracle(let value): value.status
            }
        }

        var qualified: Bool {
            switch self {
            case .domain(let value): value.qualified
            case .oracle(let value): value.qualified
            }
        }

        var metrics: Metrics {
            switch self {
            case .domain(let value): Metrics(value.caseCount, value.coverageTagCount, value.coveredRequiredCoverageTagCount, value.passRate, value.oracleAgreementRate, value.durationBudgetPassRate)
            case .oracle(let value): Metrics(value.caseCount, value.coverageTagCount, value.coveredRequiredCoverageTagCount, value.passRate, value.oracleAgreementRate, value.durationBudgetPassRate)
            }
        }

        var reportIdentity: RetainedCorpusReport.ArtifactIdentity? {
            switch self {
            case .domain(let value): value.report
            case .oracle(let value): value.report
            }
        }

        var evidenceIdentity: RetainedCorpusReport.ArtifactIdentity? {
            switch self {
            case .domain(let value): value.toolEvidenceExport
            case .oracle(let value): value.toolEvidenceExport
            }
        }
    }

    private struct Metrics {
        var caseCount: Int?
        var coverageTagCount: Int?
        var coveredRequiredCoverageTagCount: Int?
        var passRate: Double?
        var oracleAgreementRate: Double?
        var durationBudgetPassRate: Double?

        init(_ caseCount: Int?, _ coverageTagCount: Int?, _ coveredRequiredCoverageTagCount: Int?, _ passRate: Double?, _ oracleAgreementRate: Double?, _ durationBudgetPassRate: Double?) {
            self.caseCount = caseCount
            self.coverageTagCount = coverageTagCount
            self.coveredRequiredCoverageTagCount = coveredRequiredCoverageTagCount
            self.passRate = passRate
            self.oracleAgreementRate = oracleAgreementRate
            self.durationBudgetPassRate = durationBudgetPassRate
        }
    }

    private struct CorrelationDiagnostic {
        var code: String
        var message: String
    }

    private struct CorrelationOutcome {
        var blocked = false
        var diagnostics: [CorrelationDiagnostic] = []
        var failureCodes: [String] = []
    }

    private func validateOracleCorrelation(
        requiredLane: ReleaseQualificationLane,
        suite: RetainedCorpusSuite,
        report: RetainedCorpusReport
    ) -> CorrelationOutcome {
        var outcome = CorrelationOutcome()

        func block(_ code: String, _ message: String) {
            outcome.blocked = true
            outcome.diagnostics.append(CorrelationDiagnostic(code: code, message: message))
        }

        guard let native = report.domainResults.first(where: { $0.domain == requiredLane.domain }) else {
            block("QUALIFICATION_NATIVE_CORPUS_RESULT_MISSING", "External oracle correlation requires a native corpus result for the same domain.")
            return outcome
        }
        guard let oracle = report.externalOracleResults.first(where: {
            $0.domain == requiredLane.domain && $0.oracleBackendID == requiredLane.oracleBackendID
        }) else {
            block("QUALIFICATION_ORACLE_RESULT_MISSING", "External oracle correlation result is missing for the required backend and domain.")
            return outcome
        }

        let suiteCases = suite.cases.filter { $0.domain == requiredLane.domain }
        guard !suiteCases.isEmpty else {
            block("QUALIFICATION_CORPUS_CASES_MISSING", "External oracle correlation requires explicit retained corpus cases for the domain.")
            return outcome
        }

        let expectedIDs = Set(suiteCases.map(\.caseID))
        let nativeIDs = Set(native.caseResults.map(\.caseID))
        let oracleIDs = Set(oracle.caseResults.map(\.caseID))
        guard nativeIDs == expectedIDs else {
            block("QUALIFICATION_NATIVE_CASE_SET_MISMATCH", "Native corpus case IDs do not exactly match the retained suite case IDs.")
            return outcome
        }
        guard oracleIDs == expectedIDs else {
            block("QUALIFICATION_ORACLE_CASE_SET_MISMATCH", "External oracle case IDs do not exactly match the retained suite case IDs.")
            return outcome
        }

        if let caseCount = native.caseCount, caseCount != native.caseResults.count {
            block("QUALIFICATION_NATIVE_CASE_COUNT_MISMATCH", "Native corpus aggregate caseCount does not match its case-level results.")
        }
        if let caseCount = oracle.caseCount, caseCount != oracle.caseResults.count {
            block("QUALIFICATION_ORACLE_CASE_COUNT_MISMATCH", "External oracle aggregate caseCount does not match its case-level results.")
        }

        let nativeByID = Dictionary(uniqueKeysWithValues: native.caseResults.map { ($0.caseID, $0) })
        let oracleByID = Dictionary(uniqueKeysWithValues: oracle.caseResults.map { ($0.caseID, $0) })
        let requiredProbes = Set(requiredLane.requiredProbeIDs)

        for suiteCase in suiteCases.sorted(by: { $0.caseID < $1.caseID }) {
            guard let nativeCase = nativeByID[suiteCase.caseID],
                  let oracleCase = oracleByID[suiteCase.caseID] else {
                block("QUALIFICATION_CASE_RESULT_MISSING", "Native and oracle case-level results must be present for every retained case.")
                continue
            }

            if Set(suiteCase.coverageTags) != Set(nativeCase.coverageTags)
                || Set(suiteCase.coverageTags) != Set(oracleCase.coverageTags) {
                block("QUALIFICATION_CASE_COVERAGE_TAG_MISMATCH", "Native and oracle case coverage tags do not match the retained suite.")
            }
            if Set(suiteCase.probeIDs) != Set(nativeCase.probeIDs)
                || Set(suiteCase.probeIDs) != Set(oracleCase.probeIDs) {
                block("QUALIFICATION_CASE_PROBE_MISMATCH", "Native and oracle case probe IDs do not match the retained suite.")
            }
            if !requiredProbes.isSubset(of: Set(suiteCase.probeIDs)) {
                block("QUALIFICATION_ORACLE_PROBE_MISSING", "A retained oracle case does not include every probe required by the qualification lane.")
            }

            guard let agreement = oracleCase.agreement else {
                block("QUALIFICATION_CASE_AGREEMENT_MISSING", "External oracle case results must explicitly record agreement.")
                continue
            }
            if !agreement {
                outcome.failureCodes.append("ORACLE_CASE_MISMATCH")
            }
            if nativeCase.status != oracleCase.nativeStatus
                || oracleCase.nativeStatus != oracleCase.oracleStatus {
                outcome.failureCodes.append("ORACLE_CASE_STATUS_MISMATCH")
            }
        }

        outcome.failureCodes = Array(Set(outcome.failureCodes)).sorted()
        outcome.diagnostics = outcome.diagnostics.sorted { $0.code < $1.code }
        return outcome
    }

    private func validateFreshness(
        reportCreatedAt: String?,
        maximumAgeSeconds: TimeInterval,
        currentDate: Date,
        add: (_ code: String, _ message: String, _ entity: String?, _ blocked: Bool) -> Void
    ) {
        guard let reportCreatedAt, let date = parseDate(reportCreatedAt) else {
            add("QUALIFICATION_TIMESTAMP_MISSING", "Retained qualification report must include a parseable createdAt timestamp.", nil, true)
            return
        }
        let age = currentDate.timeIntervalSince(date)
        if age < 0 {
            add("QUALIFICATION_TIMESTAMP_IN_FUTURE", "Retained qualification report timestamp is in the future.", nil, true)
        } else if age > maximumAgeSeconds {
            add("QUALIFICATION_EVIDENCE_STALE", "Retained qualification report is older than the policy freshness window.", nil, true)
        }
    }

    private func validateToolEvidence(
        _ evidence: [ToolEvidence],
        evidenceArtifacts: [XcircuiteFileReference],
        policy: ReleaseQualificationPolicy,
        projectRoot: URL,
        currentDate: Date,
        add: (_ code: String, _ message: String, _ entity: String?, _ blocked: Bool) -> Void
    ) {
        for kind in Set(policy.requiredEvidenceKinds) {
            let candidates = evidence.filter { $0.kind == kind }
            let fresh = candidates.filter { item in
                guard let checkedAt = item.checkedAt else { return false }
                let age = currentDate.timeIntervalSince(checkedAt)
                return age >= 0 && age <= policy.maximumEvidenceAgeSeconds
            }
            guard !fresh.isEmpty else {
                add("QUALIFICATION_TOOL_EVIDENCE_MISSING_OR_STALE", "No fresh tool evidence is available for required evidence kind \(kind.rawValue).", kind.rawValue, true)
                continue
            }
            if policy.requiredQualifiedEvidenceKinds.contains(kind),
               !fresh.contains(where: {
                   $0.hasPassingQualificationSupport(
                       requiredScope: policy.requiredQualificationScope,
                       requireIndependentQualificationEvidence: policy.requireIndependentProcessQualification
                            && kind == .productionApproval
                   )
               }) {
                let hasScopedFailure = fresh.contains { item in
                    guard let qualification = item.qualification else {
                        return false
                    }
                    return qualification.scope == policy.requiredQualificationScope
                        && !qualification.qualified
                }
                if hasScopedFailure {
                    add("QUALIFICATION_TOOL_EVIDENCE_FAILED", "Required tool evidence contains a fresh, process-scoped qualification failure.", kind.rawValue, false)
                } else {
                    add("QUALIFICATION_TOOL_EVIDENCE_UNQUALIFIED", "Required tool evidence does not contain a passing qualification summary with the required process scope.", kind.rawValue, true)
                }
            }
        }

        guard policy.requireIndependentProcessQualification else {
            return
        }

        let productionApprovals = evidence.filter { $0.kind == .productionApproval }.filter { item in
            guard let checkedAt = item.checkedAt else { return false }
            let age = currentDate.timeIntervalSince(checkedAt)
            return age >= 0 && age <= policy.maximumEvidenceAgeSeconds
        }
        guard !productionApprovals.isEmpty else {
            add(
                "QUALIFICATION_PROCESS_EVIDENCE_MISSING",
                "Independent process qualification requires a fresh production approval evidence item.",
                ToolEvidenceKind.productionApproval.rawValue,
                true
            )
            return
        }

        var foundValidRecord = false
        for approval in productionApprovals {
            guard let artifact = approval.artifact else {
                add(
                    "QUALIFICATION_PROCESS_EVIDENCE_ARTIFACT_MISSING",
                    "Production approval evidence must reference a persisted process qualification artifact.",
                    approval.evidenceID,
                    true
                )
                continue
            }
            guard evidenceArtifacts.contains(where: { reference in
                pathsMatch(reference.path, artifact.path)
                    && reference.sha256 == artifact.sha256
                    && reference.byteCount == artifact.byteCount
            }) else {
                add(
                    "QUALIFICATION_PROCESS_EVIDENCE_ARTIFACT_UNDECLARED",
                    "Process qualification artifact is not declared in the request evidence artifacts.",
                    artifact.path,
                    true
                )
                continue
            }
            guard let url = verifier.resolvedURL(for: artifact, projectRoot: projectRoot) else {
                add(
                    "QUALIFICATION_PROCESS_EVIDENCE_PATH_INVALID",
                    "Process qualification artifact path is not a safe project-relative path.",
                    artifact.path,
                    true
                )
                continue
            }
            let record: ToolProcessQualificationEvidence
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                record = try decoder.decode(ToolProcessQualificationEvidence.self, from: data)
            } catch {
                add(
                    "QUALIFICATION_PROCESS_EVIDENCE_PARSE_FAILED",
                    "Independent process qualification artifact could not be decoded: \(error.localizedDescription)",
                    artifact.path,
                    true
                )
                continue
            }

            guard record.isQualified(
                at: currentDate,
                requirePDKScope: policy.requiredQualificationScope.isCompleteForPDK
            ) else {
                add(
                    "QUALIFICATION_PROCESS_EVIDENCE_INVALID",
                    "Independent process qualification artifact is not qualified, independent, structurally valid, or fresh.",
                    record.qualificationID,
                    true
                )
                continue
            }
            guard record.scope == policy.requiredQualificationScope else {
                add(
                    "QUALIFICATION_PROCESS_SCOPE_MISMATCH",
                    "Independent process qualification artifact scope does not match the release policy.",
                    record.qualificationID,
                    true
                )
                continue
            }
            guard let summary = approval.qualification,
                  summary.qualificationID == record.qualificationID else {
                add(
                    "QUALIFICATION_PROCESS_IDENTITY_MISMATCH",
                    "Production approval summary does not identify the independent process qualification artifact.",
                    approval.evidenceID,
                    true
                )
                continue
            }
            foundValidRecord = true
            break
        }

        if !foundValidRecord {
            add(
                "QUALIFICATION_PROCESS_EVIDENCE_UNQUALIFIED",
                "No fresh production approval contains a valid independent process qualification artifact.",
                ToolEvidenceKind.productionApproval.rawValue,
                true
            )
        }
    }

    private func matchingArtifact(for path: String?, in artifacts: [XcircuiteFileReference]) -> XcircuiteFileReference? {
        guard let path, !path.isEmpty else { return nil }
        return artifacts.first { pathsMatch($0.path, path) }
    }

    private func identityMatches(
        _ identity: RetainedCorpusReport.ArtifactIdentity?,
        reference: XcircuiteFileReference
    ) -> Bool {
        guard let identity,
              pathsMatch(identity.path, reference.path),
              identity.sha256 == reference.sha256,
              identity.byteCount == reference.byteCount else {
            return false
        }
        return true
    }

    private func pathsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let right = rhs.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return left == right || left.hasSuffix("/\(right)") || right.hasSuffix("/\(left)")
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func makeQualificationDigest(
        request: ReleaseQualificationRequest,
        laneResults: [ReleaseQualificationDomainResult]
    ) -> String {
        let material = laneResults.sorted { $0.laneID < $1.laneID }.map {
            [$0.laneID, $0.domain, $0.kind.rawValue, $0.status, $0.failureCodes.sorted().joined(separator: ",")].joined(separator: "|")
        }.joined(separator: "\n")
        let scope = request.policy.requiredQualificationScope
        let scopeMaterial = [scope.implementationID, scope.binaryDigest, scope.algorithmVersion, scope.processProfileID, scope.deckDigest].joined(separator: "|")
        return XcircuiteHasher().sha256(data: Data((request.processProfileID + "\n" + scopeMaterial + "\n" + material).utf8))
    }

    private func payload(
        request: ReleaseQualificationRequest,
        status: XcircuiteEngineExecutionStatus,
        level: ToolQualificationLevel,
        digest: String?,
        diagnostics: [XcircuiteEngineDiagnostic],
        laneResults: [ReleaseQualificationDomainResult],
        blockedLanes: Set<String>,
        failedLanes: Set<String>
    ) -> ReleaseQualificationPayload {
        let qualified = status == .completed
                && laneResults.count == request.policy.requiredLanes.count
                && blockedLanes.isEmpty
                && failedLanes.isEmpty
        let promotionStatus = qualified
            ? ReleaseQualificationPromotionStatus(rawValue: level.rawValue) ?? .blocked
            : .blocked
        return ReleaseQualificationPayload(
            qualified: qualified,
            processProfileID: request.processProfileID,
            qualificationLevel: level,
            qualificationScope: request.policy.requiredQualificationScope,
            qualificationDigest: digest,
            promotionStatus: promotionStatus,
            promotionFailureCodes: diagnostics.map(\.code).sorted(),
            laneResults: laneResults.sorted { $0.laneID < $1.laneID },
            blockedLanes: blockedLanes.sorted(),
            failedLanes: failedLanes.sorted()
        )
    }

    private func uniqueArtifacts(_ artifacts: [XcircuiteFileReference]) -> [XcircuiteFileReference] {
        Array(Set(artifacts)).sorted { $0.path < $1.path }
    }

    private func requestArtifacts(_ request: ReleaseQualificationRequest) -> [XcircuiteFileReference] {
        uniqueArtifacts(
            request.inputs
                + [request.suiteArtifact, request.qualificationReportArtifact]
                + request.corpusSpecArtifacts
                + request.domainReportArtifacts
                + request.evidenceArtifacts
        )
    }

    private func envelope(
        request: ReleaseQualificationRequest,
        status: XcircuiteEngineExecutionStatus,
        diagnostics: [XcircuiteEngineDiagnostic],
        artifacts: [XcircuiteFileReference],
        metadata: XcircuiteEngineExecutionMetadata,
        payload: ReleaseQualificationPayload
    ) -> XcircuiteEngineResultEnvelope<ReleaseQualificationPayload> {
        XcircuiteEngineResultEnvelope(
            schemaVersion: ReleaseQualificationRequest.currentSchemaVersion,
            runID: request.runID,
            status: status,
            diagnostics: diagnostics,
            artifacts: artifacts,
            metadata: metadata,
            payload: payload
        )
    }

    private func blockedEnvelope(
        request: ReleaseQualificationRequest,
        metadata: XcircuiteEngineExecutionMetadata,
        code: String,
        message: String
    ) -> XcircuiteEngineResultEnvelope<ReleaseQualificationPayload> {
        envelope(
            request: request,
            status: .blocked,
            diagnostics: [XcircuiteEngineDiagnostic(severity: .error, code: code, message: message, entity: request.runID, suggestedActions: ["inspect_qualification_request", "retain_process_scoped_evidence"])],
            artifacts: requestArtifacts(request),
            metadata: metadata,
            payload: ReleaseQualificationPayload(
                qualified: false,
                processProfileID: request.processProfileID,
                qualificationLevel: .unknown,
                qualificationScope: request.policy.requiredQualificationScope,
                qualificationDigest: nil
            )
        )
    }
}
