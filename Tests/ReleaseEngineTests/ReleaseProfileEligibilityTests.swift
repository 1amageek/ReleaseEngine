import Foundation
import QualificationEngine
import ReleaseCore
import ReleaseEngine
import Testing
import ToolQualification
import CircuiteFoundation

@Suite("Release profile eligibility")
struct ReleaseProfileEligibilityTests {
    @Test("eligible profile requires three completed stages and a human-bound packet approval")
    func eligibleProfile() async throws {
        let runID = "release-profile-positive"
        let request = makeRequest(
            runID: runID,
            qualificationLevel: .productionEligible,
            promotionStatus: .productionEligible,
            reviewerKind: .human,
            approvalPacketDigest: String(repeating: "d", count: 64)
        )

        let envelope = try await DefaultReleaseProfileEligibilityEvaluator().execute(request)

        #expect(envelope.status == .completed)
        #expect(envelope.payload.eligible)
        #expect(envelope.payload.status == .eligible)
        #expect(envelope.payload.failureCodes.isEmpty)
        #expect(envelope.payload.reviewedArtifactDigests.count == 3)
        #expect(envelope.payload.evidenceDigest?.count == 64)
    }

    @Test("corpus-only evidence and non-human approval remain blocked")
    func insufficientQualificationAndApproval() async throws {
        let request = makeRequest(
            runID: "release-profile-blocked",
            qualificationLevel: .corpusChecked,
            promotionStatus: .corpusChecked,
            reviewerKind: .agent,
            approvalPacketDigest: String(repeating: "e", count: 64),
            approvalMatchesPacket: false
        )

        let envelope = try await DefaultReleaseProfileEligibilityEvaluator().execute(request)

        #expect(envelope.status == .blocked)
        #expect(envelope.payload.eligible == false)
        #expect(envelope.payload.status == .blocked)
        #expect(envelope.payload.failureCodes.contains("release-profile-qualification-level-insufficient"))
        #expect(envelope.payload.failureCodes.contains("release-profile-promotion-status-insufficient"))
        #expect(envelope.payload.failureCodes.contains("release-profile-human-review-required"))
        #expect(envelope.payload.failureCodes.contains("release-profile-approval-decision-packet-mismatch"))
    }

    @Test("production qualification requires an exact process qualification scope")
    func qualificationScopeMismatchBlocksEligibility() async throws {
        var request = makeRequest(
            runID: "release-profile-scope-mismatch",
            qualificationLevel: .productionEligible,
            promotionStatus: .productionEligible,
            reviewerKind: .human,
            approvalPacketDigest: String(repeating: "d", count: 64)
        )
        request.qualification.qualificationScope?.deckDigest = String(repeating: "e", count: 64)

        let envelope = try await DefaultReleaseProfileEligibilityEvaluator().execute(request)

        #expect(envelope.status == .blocked)
        #expect(envelope.payload.failureCodes.contains("release-profile-qualification-scope-mismatch"))
    }

    @Test("production qualification requires a PDK-bound scope")
    func productionQualificationWithoutPDKScopeBlocksEligibility() async throws {
        var request = makeRequest(
            runID: "release-profile-pdk-scope-missing",
            qualificationLevel: .productionEligible,
            requiredQualificationLevel: .productionEligible,
            promotionStatus: .productionEligible,
            reviewerKind: .human,
            approvalPacketDigest: String(repeating: "d", count: 64)
        )
        let requiredScope = ToolQualificationScope(
            implementationID: "native.release.qualification",
            binaryDigest: String(repeating: "3", count: 64),
            algorithmVersion: "qualification-v1",
            processProfileID: "sky130",
            deckDigest: String(repeating: "4", count: 64)
        )
        request.requiredQualificationScope = requiredScope
        request.qualification.qualificationScope = requiredScope

        let envelope = try await DefaultReleaseProfileEligibilityEvaluator().execute(request)

        #expect(envelope.status == .blocked)
        #expect(envelope.payload.failureCodes.contains("release-profile-qualification-pdk-scope-incomplete"))
    }

    @Test("eligibility request and result envelope round-trip deterministically")
    func codableRoundTrip() throws {
        let request = makeRequest(
            runID: "release-profile-round-trip",
            qualificationLevel: .oracleChecked,
            promotionStatus: .oracleChecked,
            reviewerKind: .human,
            approvalPacketDigest: String(repeating: "d", count: 64)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decodedRequest = try decoder.decode(
            ReleaseProfileEligibilityRequest.self,
            from: encoder.encode(request)
        )
        #expect(decodedRequest == request)

        let envelope = try DefaultReleaseProfileEligibilityResultFactory.make(
            request: request
        )
        let decodedEnvelope = try decoder.decode(
            ReleaseProfileEligibilityResult.self,
            from: encoder.encode(envelope)
        )
        #expect(decodedEnvelope == envelope)
    }

    @Test("checked-in blocked eligibility fixture decodes")
    func blockedFixtureDecodes() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/Eligibility/blocked/request.json")
        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let request = try decoder.decode(ReleaseProfileEligibilityRequest.self, from: data)
        #expect(request.runID == "release-profile-blocked-fixture")
        #expect(request.approval.reviewerKind == .agent)
    }

    private func makeRequest(
        runID: String,
        qualificationLevel: ToolQualificationLevel,
        requiredQualificationLevel: ToolQualificationLevel = .oracleChecked,
        promotionStatus: ReleaseProfileRequiredPromotionStatus,
        reviewerKind: ReleaseApprovalRecord.ReviewerKind,
        approvalPacketDigest: String,
        approvalMatchesPacket: Bool = true
    ) -> ReleaseProfileEligibilityRequest {
        let designDigest = String(repeating: "1", count: 64)
        let pdkDigest = String(repeating: "2", count: 64)
        let qualificationScope = ToolQualificationScope(
            implementationID: "native.release.qualification",
            binaryDigest: String(repeating: "3", count: 64),
            algorithmVersion: "qualification-v1",
            processProfileID: "sky130",
            deckDigest: String(repeating: "4", count: 64),
            pdkID: "sky130A",
            pdkDigest: pdkDigest
        )
        let packet = artifact(id: "decision-packet", digest: approvalPacketDigest)
        let approval = ReleaseApprovalRecord(
            runID: runID,
            stageID: "release.profile",
            verdict: .approved,
            reviewer: "release-reviewer",
            reviewerKind: reviewerKind,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            stageResultSHA256: approvalMatchesPacket
                ? packet.sha256
                : String(repeating: "f", count: 64),
            stageResultByteCount: Int64(packet.byteCount)
        )
        return ReleaseProfileEligibilityRequest(
            runID: runID,
            profileID: "digital",
            processProfileID: "sky130",
            requiredQualificationLevel: requiredQualificationLevel,
            requiredPromotionStatus: .oracleChecked,
            requiredQualificationScope: qualificationScope,
            signoff: ReleaseProfileStageEvidence(
                stageID: "release.signoff",
                runID: runID,
                status: .completed,
                resultArtifact: artifact(id: "signoff", digest: String(repeating: "a", count: 64)),
                profileID: "digital",
                processProfileID: "sky130",
                designDigest: designDigest,
                pdkDigest: pdkDigest,
                approved: true
            ),
            qualification: ReleaseProfileStageEvidence(
                stageID: "release.qualification",
                runID: runID,
                status: .completed,
                resultArtifact: artifact(id: "qualification", digest: String(repeating: "b", count: 64)),
                processProfileID: "sky130",
                qualified: true,
                qualificationLevel: qualificationLevel,
                promotionStatus: promotionStatus.qualificationValue,
                qualificationDigest: String(repeating: "9", count: 64),
                qualificationScope: qualificationScope
            ),
            tapeout: ReleaseProfileStageEvidence(
                stageID: "release.tapeout",
                runID: runID,
                status: .completed,
                resultArtifact: artifact(id: "tapeout", digest: String(repeating: "c", count: 64)),
                processProfileID: "sky130",
                designDigest: designDigest,
                pdkDigest: pdkDigest,
                approved: true
            ),
            decisionPacketArtifact: packet,
            approval: approval
        )
    }

    private func artifact(id: String, digest: String) -> ArtifactReference {
        makeTestArtifactReference(
            artifactID: id,
            path: "runs/release-profile/\(id).json",
            kind: .report,
            format: .json,
            sha256: digest,
            byteCount: 10
        )
    }
}

private extension ReleaseProfileRequiredPromotionStatus {
    var qualificationValue: ReleaseQualificationPromotionStatus {
        switch self {
        case .corpusChecked:
            .corpusChecked
        case .oracleChecked:
            .oracleChecked
        case .productionEligible:
            .productionEligible
        }
    }
}

private enum DefaultReleaseProfileEligibilityResultFactory {
    static func make(
        request: ReleaseProfileEligibilityRequest
    ) throws -> ReleaseProfileEligibilityResult {
        try makeAsync(request: request)
    }

    private static func makeAsync(
        request: ReleaseProfileEligibilityRequest
    ) throws -> ReleaseProfileEligibilityResult {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let payload = ReleaseProfileEligibilityPayload(
            eligible: false,
            status: .blocked,
            profileID: request.profileID,
            processProfileID: request.processProfileID,
            requiredQualificationLevel: request.requiredQualificationLevel,
            requiredPromotionStatus: request.requiredPromotionStatus,
            decisionPacketDigest: request.decisionPacketArtifact.sha256
        )
        return ReleaseProfileEligibilityResult(
            schemaVersion: 1,
            runID: request.runID,
            status: .blocked,
            metadata: try ExecutionProvenance(
                producer: try ProducerIdentity(
                    kind: .engine,
                    identifier: "release.profile.eligibility",
                    version: "1.0.0"
                ),
                startedAt: date,
                completedAt: date
            ),
            payload: payload
        )
    }
}
