import CryptoKit
import CircuiteFoundation
import Foundation
import QualificationEngine
import ToolQualification

/// Deterministic, fail-closed Foundation implementation of release-profile eligibility.
public struct DefaultFoundationReleaseProfileEligibilityEvaluator:
    FoundationReleaseProfileEligibilityEngine
{
    private let producer: ProducerIdentity
    private let now: @Sendable () -> Date

    public init(
        producer: ProducerIdentity,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.producer = producer
        self.now = now
    }

    public func execute(
        _ request: FoundationReleaseProfileEligibilityRequest
    ) async throws -> FoundationReleaseProfileEligibilityResult {
        try Task.checkCancellation()
        let startedAt = now()
        var failures: [String] = []

        func add(_ code: String) {
            if !failures.contains(code) {
                failures.append(code)
            }
        }

        if request.schemaVersion != FoundationReleaseProfileEligibilityRequest.currentSchemaVersion {
            add("release-profile-schema-unsupported")
        }
        if request.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("release-profile-run-id-missing")
        }
        if request.profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("release-profile-profile-id-missing")
        }
        if request.processProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("release-profile-process-profile-id-missing")
        }

        let stages = [request.signoff, request.qualification, request.tapeout]
        let expectedStageIDs = ["release.signoff", "release.qualification", "release.tapeout"]
        let requiredInputs = Set(stages.map(\.resultArtifact) + [request.decisionPacketArtifact])
        let suppliedInputs = Set(request.inputs)
        if !requiredInputs.isSubset(of: suppliedInputs) {
            add("release-profile-inputs-incomplete")
        }
        for input in request.inputs {
            validateArtifact(input, codePrefix: "release-profile-input-artifact", add: add)
        }
        if stages.map(\.stageID) != expectedStageIDs {
            add("release-profile-stage-order-invalid")
        }
        for stage in stages {
            if stage.schemaVersion != FoundationReleaseProfileStageEvidence.currentSchemaVersion {
                add("release-profile-stage-schema-unsupported")
            }
            if stage.runID != request.runID {
                add("release-profile-stage-run-id-mismatch")
            }
            if stage.status != .completed {
                add("release-profile-stage-not-completed")
            }
            validateArtifact(stage.resultArtifact, codePrefix: "release-profile-stage-artifact", add: add)
        }

        if request.signoff.profileID != request.profileID {
            add("release-profile-signoff-profile-mismatch")
        }
        if request.qualification.profileID != request.profileID {
            add("release-profile-qualification-profile-mismatch")
        }
        if request.tapeout.profileID != request.profileID {
            add("release-profile-tapeout-profile-mismatch")
        }
        if !request.signoff.approved {
            add("release-profile-signoff-not-approved")
        }
        if stages.contains(where: { $0.processProfileID != request.processProfileID }) {
            add("release-profile-process-profile-mismatch")
        }
        if !request.qualification.qualified {
            add("release-profile-qualification-not-qualified")
        }
        validateQualification(
            request.qualification,
            request: request,
            add: add
        )
        if !request.tapeout.approved {
            add("release-profile-tapeout-not-approved")
        }

        let designRevisions = stages.compactMap(\.designRevision)
        if designRevisions.count != stages.count
            || designRevisions.dropFirst().contains(where: { $0 != designRevisions[0] })
        {
            add("release-profile-design-digest-mismatch")
        }
        let pdkRevisions = stages.compactMap(\.pdkRevision)
        if pdkRevisions.count != stages.count
            || pdkRevisions.dropFirst().contains(where: { $0 != pdkRevisions[0] })
        {
            add("release-profile-pdk-digest-mismatch")
        }

        validateArtifact(request.decisionPacketArtifact, codePrefix: "release-profile-decision-packet", add: add)
        if request.approval.runID != request.runID {
            add("release-profile-approval-run-id-mismatch")
        }
        if request.approval.stageID != "release.profile" {
            add("release-profile-approval-stage-mismatch")
        }
        if request.approval.verdict != .approved {
            add("release-profile-approval-not-approved")
        }
        if request.approval.reviewerKind != .human
            || request.approval.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            add("release-profile-human-review-required")
        }
        if !request.approval.createdAt.timeIntervalSinceReferenceDate.isFinite {
            add("release-profile-approval-timestamp-invalid")
        }
        if request.approval.stageResultDigest != request.decisionPacketArtifact.digest {
            add("release-profile-approval-decision-packet-mismatch")
        }

        let reviewedArtifacts = stages.map(\.resultArtifact)
        let evidenceDigest = try makeEvidenceDigest(
            request: request,
            reviewedArtifacts: reviewedArtifacts
        )
        let sortedFailures = failures.sorted()
        let diagnostics = try sortedFailures.map { code in
            let diagnosticCode: DiagnosticCode
            do {
                diagnosticCode = try DiagnosticCode(rawValue: code)
            } catch {
                throw FoundationReleaseProfileEligibilityError.invalidDiagnosticCode(code)
            }
            return DesignDiagnostic(
                code: diagnosticCode,
                severity: .error,
                summary: "Release profile eligibility is blocked by \(code)."
            )
        }
        let completedAt = now()
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: request.inputs,
            designRevision: request.signoff.designRevision,
            startedAt: startedAt,
            completedAt: completedAt
        )
        try Task.checkCancellation()
        return FoundationReleaseProfileEligibilityResult(
            eligible: sortedFailures.isEmpty,
            status: sortedFailures.isEmpty ? .eligible : .blocked,
            profileID: request.profileID,
            processProfileID: request.processProfileID,
            requiredQualificationLevel: request.requiredQualificationLevel,
            requiredPromotionStatus: request.requiredPromotionStatus,
            qualificationDigest: request.qualification.qualificationDigest,
            decisionPacketArtifact: request.decisionPacketArtifact,
            reviewedArtifacts: reviewedArtifacts,
            evidenceDigest: evidenceDigest,
            failureCodes: sortedFailures,
            diagnostics: diagnostics,
            provenance: provenance
        )
    }

    private func validateQualification(
        _ qualification: FoundationReleaseProfileStageEvidence,
        request: FoundationReleaseProfileEligibilityRequest,
        add: (String) -> Void
    ) {
        if request.requiredQualificationLevel >= .oracleChecked {
            if let requiredScope = request.requiredQualificationScope {
                if !requiredScope.isComplete || qualification.qualificationScope?.isComplete != true {
                    add("release-profile-qualification-scope-incomplete")
                } else {
                    if request.requiredQualificationLevel >= .productionEligible
                        && (!requiredScope.isCompleteForPDK || qualification.qualificationScope?.isCompleteForPDK != true)
                    {
                        add("release-profile-qualification-pdk-scope-incomplete")
                    } else if qualification.qualificationScope != requiredScope {
                        add("release-profile-qualification-scope-mismatch")
                    }
                    if requiredScope.processProfileID != request.processProfileID {
                        add("release-profile-qualification-scope-process-mismatch")
                    }
                }
            } else {
                add("release-profile-qualification-scope-missing")
            }
        }
        guard let qualificationDigest = qualification.qualificationDigest else {
            add("release-profile-qualification-digest-missing")
            validateQualificationLevelAndPromotion(qualification, request: request, add: add)
            return
        }
        if qualificationDigest.algorithm != .sha256 {
            add("release-profile-qualification-digest-invalid")
        }
        validateQualificationLevelAndPromotion(
            qualification,
            request: request,
            add: add
        )
    }

    private func validateQualificationLevelAndPromotion(
        _ qualification: FoundationReleaseProfileStageEvidence,
        request: FoundationReleaseProfileEligibilityRequest,
        add: (String) -> Void
    ) {
        if let level = qualification.qualificationLevel {
            if level < request.requiredQualificationLevel {
                add("release-profile-qualification-level-insufficient")
            }
        } else {
            add("release-profile-qualification-level-missing")
        }
        if let promotionStatus = qualification.promotionStatus {
            if promotionRank(promotionStatus) < request.requiredPromotionStatus.rank {
                add("release-profile-promotion-status-insufficient")
            }
        } else {
            add("release-profile-promotion-status-missing")
        }
    }

    private func validateArtifact(
        _ artifact: ArtifactReference,
        codePrefix: String,
        add: (String) -> Void
    ) {
        if artifact.byteCount == 0 {
            add("\(codePrefix)-byte-count-invalid")
        }
        if artifact.digest.algorithm != .sha256 {
            add("\(codePrefix)-digest-invalid")
        }
    }

    private func makeEvidenceDigest(
        request: FoundationReleaseProfileEligibilityRequest,
        reviewedArtifacts: [ArtifactReference]
    ) throws -> ContentDigest {
        let material = [
            request.runID,
            request.profileID,
            request.processProfileID,
            request.requiredQualificationLevel.rawValue,
            request.requiredPromotionStatus.rawValue,
            request.signoff.resultArtifact.digest.hexadecimalValue,
            request.qualification.resultArtifact.digest.hexadecimalValue,
            request.tapeout.resultArtifact.digest.hexadecimalValue,
            request.decisionPacketArtifact.digest.hexadecimalValue,
            reviewedArtifacts.map { $0.digest.hexadecimalValue }.sorted().joined(separator: ","),
            request.approval.reviewer,
            ISO8601DateFormatter().string(from: request.approval.createdAt),
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(material.utf8))
        return try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    private func promotionRank(_ status: ReleaseQualificationPromotionStatus) -> Int {
        switch status {
        case .blocked: 0
        case .corpusChecked: 1
        case .oracleChecked: 2
        case .productionEligible: 3
        }
    }
}
