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
        if request.policy.requiredQualificationLevel > .oracleChecked {
            return blockedEnvelope(request: request, metadata: metadata, code: "QUALIFICATION_LEVEL_NOT_IMPLEMENTED", message: "Production eligibility promotion requires the later process-promotion milestone.")
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
                payload: payload(request: request, status: status, level: .unknown, digest: nil, laneResults: laneResults, blockedLanes: blockedLanes, failedLanes: failedLanes)
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
        validateToolEvidence(request.toolEvidence, policy: request.policy, currentDate: now(), add: add)

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
                        && (requiredLane.oracleBackendID == nil || $0.oracleBackendID == requiredLane.oracleBackendID)
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
                guard let oracleAgreementRate = metrics.oracleAgreementRate else {
                    blockedLanes.insert(requiredLane.laneID)
                    add("QUALIFICATION_ORACLE_AGREEMENT_MISSING", "External oracle lane has no oracle agreement metric.", entity: requiredLane.laneID, blocked: true)
                    continue
                }
                if oracleAgreementRate < request.policy.minimumOracleAgreementRate { failureCodes.append("ORACLE_AGREEMENT_BELOW_THRESHOLD") }
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
                reportArtifact: reportArtifact,
                evidenceArtifact: evidenceArtifact
            ))
        }

        let level: ToolQualificationLevel = request.policy.requiredLanes.contains { $0.kind == .externalOracle } ? .oracleChecked : .corpusChecked
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
            payload: payload(request: request, status: status, level: level, digest: qualificationDigest, laneResults: laneResults, blockedLanes: blockedLanes, failedLanes: failedLanes)
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
        policy: ReleaseQualificationPolicy,
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
               !fresh.contains(where: { $0.hasPassingQualificationSupport(requiredScope: policy.requiredQualificationScope) }) {
                add("QUALIFICATION_TOOL_EVIDENCE_UNQUALIFIED", "Required tool evidence does not contain a passing qualification summary with the required process scope.", kind.rawValue, true)
            }
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
        laneResults: [ReleaseQualificationDomainResult],
        blockedLanes: Set<String>,
        failedLanes: Set<String>
    ) -> ReleaseQualificationPayload {
        ReleaseQualificationPayload(
            qualified: status == .completed
                && laneResults.count == request.policy.requiredLanes.count
                && blockedLanes.isEmpty
                && failedLanes.isEmpty,
            processProfileID: request.processProfileID,
            qualificationLevel: level,
            qualificationScope: request.policy.requiredQualificationScope,
            qualificationDigest: digest,
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
