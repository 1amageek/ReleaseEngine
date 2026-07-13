import CircuiteFoundation
import Foundation
import QualificationEngine
import ReleaseCore
import ReleaseEngine
import Testing
import ToolQualification

@Suite("Foundation release profile eligibility")
struct FoundationReleaseProfileEligibilityTests {
    @Test("eligible result carries immutable artifacts, diagnostics, and provenance")
    func eligibleResult() async throws {
        let request = try makeRequest()
        let producer = try ProducerIdentity(
            kind: .engine,
            identifier: "release-engine",
            version: "1.0.0"
        )
        let evaluator = DefaultFoundationReleaseProfileEligibilityEvaluator(
            producer: producer,
            now: { Date(timeIntervalSince1970: 101) }
        )

        let result = try await evaluator.execute(request)

        #expect(result.eligible)
        #expect(result.failureCodes.isEmpty)
        #expect(result.diagnostics.isEmpty)
        #expect(result.artifacts.count == 4)
        #expect(result.evidence.provenance.producer == producer)
        #expect(result.evidence.provenance.startedAt == Date(timeIntervalSince1970: 101))
        #expect(result.evidence.provenance.completedAt == Date(timeIntervalSince1970: 101))
        #expect(result.evidenceDigest?.algorithm == .sha256)
    }

    @Test("non-human approval and incomplete qualification remain blocked")
    func blockedResult() async throws {
        var request = try makeRequest()
        request = FoundationReleaseProfileEligibilityRequest(
            runID: request.runID,
            profileID: request.profileID,
            processProfileID: request.processProfileID,
            requiredQualificationLevel: .productionEligible,
            requiredPromotionStatus: .productionEligible,
            requiredQualificationScope: request.requiredQualificationScope,
            signoff: request.signoff,
            qualification: FoundationReleaseProfileStageEvidence(
                stageID: request.qualification.stageID,
                runID: request.qualification.runID,
                status: request.qualification.status,
                resultArtifact: request.qualification.resultArtifact,
                profileID: request.qualification.profileID,
                processProfileID: request.qualification.processProfileID,
                designRevision: request.qualification.designRevision,
                pdkRevision: request.qualification.pdkRevision,
                approved: request.qualification.approved,
                qualified: request.qualification.qualified,
                qualificationLevel: .corpusChecked,
                promotionStatus: .corpusChecked,
                qualificationDigest: request.qualification.qualificationDigest,
                qualificationScope: request.qualification.qualificationScope
            ),
            tapeout: request.tapeout,
            decisionPacketArtifact: request.decisionPacketArtifact,
            approval: FoundationReleaseProfileApproval(
                runID: request.approval.runID,
                stageID: request.approval.stageID,
                verdict: request.approval.verdict,
                reviewer: request.approval.reviewer,
                reviewerKind: .agent,
                note: request.approval.note,
                createdAt: request.approval.createdAt,
                stageResultDigest: nil
            ),
            inputs: request.inputs
        )
        let evaluator = DefaultFoundationReleaseProfileEligibilityEvaluator(
            producer: try ProducerIdentity(kind: .engine, identifier: "release-engine", version: "1.0.0"),
            now: { Date(timeIntervalSince1970: 101) }
        )

        let result = try await evaluator.execute(request)

        #expect(!result.eligible)
        #expect(result.status == .blocked)
        #expect(result.failureCodes.contains("release-profile-qualification-level-insufficient"))
        #expect(result.failureCodes.contains("release-profile-promotion-status-insufficient"))
        #expect(result.failureCodes.contains("release-profile-human-review-required"))
        #expect(result.failureCodes.contains("release-profile-approval-decision-packet-mismatch"))
        #expect(result.diagnostics.count == result.failureCodes.count)
    }

    @Test("Foundation request round-trips through sorted JSON")
    func codableRoundTrip() throws {
        let request = try makeRequest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            FoundationReleaseProfileEligibilityRequest.self,
            from: encoder.encode(request)
        )

        #expect(decoded == request)
    }

    @Test("input completeness compares immutable artifact references, not only IDs")
    func inputCompletenessBindsArtifactContent() async throws {
        let request = try makeRequest()
        let original = request.qualification.resultArtifact
        let replacement = ArtifactReference(
            id: original.id,
            locator: original.locator,
            digest: try digest("6"),
            byteCount: original.byteCount
        )
        let inputs = request.inputs.map { $0 == original ? replacement : $0 }
        let tamperedRequest = FoundationReleaseProfileEligibilityRequest(
            runID: request.runID,
            profileID: request.profileID,
            processProfileID: request.processProfileID,
            requiredQualificationLevel: request.requiredQualificationLevel,
            requiredPromotionStatus: request.requiredPromotionStatus,
            requiredQualificationScope: request.requiredQualificationScope,
            signoff: request.signoff,
            qualification: request.qualification,
            tapeout: request.tapeout,
            decisionPacketArtifact: request.decisionPacketArtifact,
            approval: request.approval,
            inputs: inputs
        )
        let evaluator = DefaultFoundationReleaseProfileEligibilityEvaluator(
            producer: try ProducerIdentity(kind: .engine, identifier: "release-engine", version: "1.0.0"),
            now: { Date(timeIntervalSince1970: 101) }
        )

        let result = try await evaluator.execute(tamperedRequest)

        #expect(result.failureCodes.contains("release-profile-inputs-incomplete"))
        #expect(!result.eligible)
    }

    private func makeRequest() throws -> FoundationReleaseProfileEligibilityRequest {
        let runID = "foundation-release-profile"
        let designRevision = try digest("1")
        let pdkRevision = try digest("2")
        let qualificationDigest = try digest("3")
        let stageDigest = try digest("4")
        let decisionDigest = try digest("5")
        let scope = ToolQualificationScope(
            implementationID: "native.release.qualification",
            binaryDigest: String(repeating: "a", count: 64),
            algorithmVersion: "qualification-v1",
            processProfileID: "sky130",
            deckDigest: String(repeating: "b", count: 64),
            pdkID: "sky130A",
            pdkDigest: String(repeating: "c", count: 64)
        )

        let signoffArtifact = try artifact("signoff.json", digest: stageDigest)
        let qualificationArtifact = try artifact("qualification.json", digest: stageDigest)
        let tapeoutArtifact = try artifact("tapeout.json", digest: stageDigest)
        let decisionArtifact = try artifact("decision.json", digest: decisionDigest)
        let makeStage: (String, ArtifactReference, Bool, Bool) -> FoundationReleaseProfileStageEvidence = {
            stageID, artifact, approved, qualified in
            FoundationReleaseProfileStageEvidence(
                stageID: stageID,
                runID: runID,
                status: .completed,
                resultArtifact: artifact,
                profileID: "digital",
                processProfileID: "sky130",
                designRevision: designRevision,
                pdkRevision: pdkRevision,
                approved: approved,
                qualified: qualified,
                qualificationLevel: .productionEligible,
                promotionStatus: .productionEligible,
                qualificationDigest: qualificationDigest,
                qualificationScope: scope
            )
        }

        return FoundationReleaseProfileEligibilityRequest(
            runID: runID,
            profileID: "digital",
            processProfileID: "sky130",
            requiredQualificationLevel: .productionEligible,
            requiredPromotionStatus: .productionEligible,
            requiredQualificationScope: scope,
            signoff: makeStage("release.signoff", signoffArtifact, true, false),
            qualification: makeStage("release.qualification", qualificationArtifact, false, true),
            tapeout: makeStage("release.tapeout", tapeoutArtifact, true, false),
            decisionPacketArtifact: decisionArtifact,
            approval: FoundationReleaseProfileApproval(
                runID: runID,
                stageID: "release.profile",
                verdict: .approved,
                reviewer: "release-reviewer",
                createdAt: Date(timeIntervalSince1970: 100),
                stageResultDigest: decisionDigest
            )
        )
    }

    private func artifact(_ path: String, digest: ContentDigest) throws -> ArtifactReference {
        ArtifactReference(
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "runs/\(path)"),
                role: .input,
                kind: .report,
                format: .json
            ),
            digest: digest,
            byteCount: 1
        )
    }

    private func digest(_ nibble: String) throws -> ContentDigest {
        try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: nibble, count: 64)
        )
    }
}
