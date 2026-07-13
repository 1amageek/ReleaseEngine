import Foundation
import ReleaseCore
import QualificationEngine
import ToolQualification
import XcircuitePackage

public struct DefaultReleaseProfileEligibilityEvaluator: ReleaseProfileEligibilityEvaluating {
    public init() {}

    public func execute(
        _ request: ReleaseProfileEligibilityRequest
    ) async throws -> ReleaseProfileEligibilityEnvelope {
        let startedAt = Date()
        var failures: [String] = []
        func add(_ code: String) {
            if !failures.contains(code) {
                failures.append(code)
            }
        }

        if request.schemaVersion != ReleaseProfileEligibilityRequest.currentSchemaVersion {
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
        if stages.map(\.stageID) != expectedStageIDs {
            add("release-profile-stage-order-invalid")
        }
        for stage in stages {
            if stage.schemaVersion != ReleaseProfileStageEvidence.currentSchemaVersion {
                add("release-profile-stage-schema-unsupported")
            }
            if stage.runID != request.runID {
                add("release-profile-stage-run-id-mismatch")
            }
            if stage.status != .completed {
                add("release-profile-stage-not-completed")
            }
            validateArtifact(
                stage.resultArtifact,
                codePrefix: "release-profile-stage-artifact",
                runID: request.runID,
                add: add
            )
        }

        if request.signoff.profileID != request.profileID {
            add("release-profile-signoff-profile-mismatch")
        }
        if request.signoff.approved == false {
            add("release-profile-signoff-not-approved")
        }
        if request.qualification.processProfileID != request.processProfileID
            || request.tapeout.processProfileID != request.processProfileID {
            add("release-profile-process-profile-mismatch")
        }
        if request.qualification.qualified == false {
            add("release-profile-qualification-not-qualified")
        }
        if request.requiredQualificationLevel >= .oracleChecked {
            if let requiredScope = request.requiredQualificationScope {
                if !requiredScope.isComplete || request.qualification.qualificationScope?.isComplete != true {
                    add("release-profile-qualification-scope-incomplete")
                } else if request.requiredQualificationLevel >= .productionEligible
                    && (!requiredScope.isCompleteForPDK
                        || request.qualification.qualificationScope?.isCompleteForPDK != true) {
                    add("release-profile-qualification-pdk-scope-incomplete")
                } else {
                    if request.qualification.qualificationScope != requiredScope {
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
        if let qualificationDigest = request.qualification.qualificationDigest {
            if !isSHA256(qualificationDigest) {
                add("release-profile-qualification-digest-invalid")
            }
        } else {
            add("release-profile-qualification-digest-missing")
        }
        if let level = request.qualification.qualificationLevel {
            if level < request.requiredQualificationLevel {
                add("release-profile-qualification-level-insufficient")
            }
        } else {
            add("release-profile-qualification-level-missing")
        }
        if let promotionStatus = request.qualification.promotionStatus {
            if promotionRank(promotionStatus) < request.requiredPromotionStatus.rank {
                add("release-profile-promotion-status-insufficient")
            }
        } else {
            add("release-profile-promotion-status-missing")
        }
        if request.tapeout.approved == false {
            add("release-profile-tapeout-not-approved")
        }

        let designDigests = [request.signoff.designDigest, request.tapeout.designDigest].compactMap { $0 }
        if designDigests.count != 2 || designDigests[0] != designDigests[1] {
            add("release-profile-design-digest-mismatch")
        }
        let pdkDigests = [request.signoff.pdkDigest, request.tapeout.pdkDigest].compactMap { $0 }
        if pdkDigests.count != 2 || pdkDigests[0] != pdkDigests[1] {
            add("release-profile-pdk-digest-mismatch")
        }

        validateArtifact(
            request.decisionPacketArtifact,
            codePrefix: "release-profile-decision-packet",
            runID: request.runID,
            add: add
        )
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
            || request.approval.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("release-profile-human-review-required")
        }
        if request.approval.stageResultSHA256 != request.decisionPacketArtifact.sha256 {
            add("release-profile-approval-decision-packet-mismatch")
        }

        let reviewedArtifactDigests = stages.compactMap(\.resultArtifact.sha256).sorted()
        let evidenceDigest = Self.evidenceDigest(
            request: request,
            reviewedArtifactDigests: reviewedArtifactDigests
        )
        let qualified = failures.isEmpty
        let payload = ReleaseProfileEligibilityPayload(
            eligible: qualified,
            status: qualified ? .eligible : .blocked,
            profileID: request.profileID,
            processProfileID: request.processProfileID,
            requiredQualificationLevel: request.requiredQualificationLevel,
            requiredPromotionStatus: request.requiredPromotionStatus,
            qualificationDigest: request.qualification.qualificationDigest,
            decisionPacketDigest: request.decisionPacketArtifact.sha256,
            reviewedArtifactDigests: reviewedArtifactDigests,
            evidenceDigest: evidenceDigest,
            failureCodes: failures.sorted()
        )
        let completedAt = Date()
        return XcircuiteEngineResultEnvelope(
            schemaVersion: 1,
            runID: request.runID,
            status: qualified ? .completed : .blocked,
            diagnostics: failures.sorted().map { code in
                XcircuiteEngineDiagnostic(
                    severity: .error,
                    code: code,
                    message: "Release profile eligibility is blocked by \(code)."
                )
            },
            artifacts: [request.decisionPacketArtifact],
            metadata: XcircuiteEngineExecutionMetadata(
                engineID: "release.profile.eligibility",
                implementationID: "native.release.profile.eligibility",
                implementationVersion: "1.0.0",
                startedAt: startedAt,
                completedAt: completedAt
            ),
            payload: payload
        )
    }

    private func validateArtifact(
        _ artifact: XcircuiteFileReference,
        codePrefix: String,
        runID: String,
        add: (String) -> Void
    ) {
        if artifact.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("\(codePrefix)-path-missing")
        }
        guard let sha256 = artifact.sha256, isSHA256(sha256) else {
            add("\(codePrefix)-digest-missing")
            return
        }
        if let byteCount = artifact.byteCount, byteCount <= 0 {
            add("\(codePrefix)-byte-count-invalid")
        } else if artifact.byteCount == nil {
            add("\(codePrefix)-byte-count-missing")
        }
        if let producedByRunID = artifact.producedByRunID,
           producedByRunID != runID {
            add("\(codePrefix)-run-id-mismatch")
        }
    }

    private static func evidenceDigest(
        request: ReleaseProfileEligibilityRequest,
        reviewedArtifactDigests: [String]
    ) -> String {
        let material = [
            request.runID,
            request.profileID,
            request.processProfileID,
            request.requiredQualificationLevel.rawValue,
            request.requiredPromotionStatus.rawValue,
            request.signoff.resultArtifact.sha256 ?? "",
            request.qualification.resultArtifact.sha256 ?? "",
            request.tapeout.resultArtifact.sha256 ?? "",
            request.decisionPacketArtifact.sha256 ?? "",
            reviewedArtifactDigests.joined(separator: ","),
            request.approval.reviewer,
            request.approval.createdAt.iso8601String,
        ].joined(separator: "\n")
        return XcircuiteHasher().sha256(data: Data(material.utf8))
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { character in
            character.isNumber || ("a"..."f").contains(character) || ("A"..."F").contains(character)
        }
    }

    private func promotionRank(_ status: ReleaseQualificationPromotionStatus) -> Int {
        switch status {
        case .blocked:
            0
        case .corpusChecked:
            1
        case .oracleChecked:
            2
        case .productionEligible:
            3
        }
    }
}

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
