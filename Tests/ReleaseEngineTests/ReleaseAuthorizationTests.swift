import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore
import ReleaseEngine
import Testing
import ToolQualification

@Suite("Release authorization")
struct ReleaseAuthorizationTests {
    @Test("human approval and independently reproducible trust authorize an exact signoff bundle")
    func authorizesBoundInputs() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }

        let result = try await fixture.authorizer().execute(fixture.request())

        #expect(result.status == .authorized)
        #expect(result.signoffBundle == fixture.bundleReference)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("agent approval fails closed")
    func rejectsAgentApproval() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        var request = fixture.request()
        request = fixture.request(approval: FlowApprovalRecord(
            runID: request.runID,
            stageID: request.stageID,
            verdict: .approved,
            reviewer: "agent",
            reviewerKind: .agent,
            createdAt: request.evaluatedAt,
            evidence: request.approval.evidence
        ))

        let result = try await fixture.authorizer().execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "HUMAN_RELEASE_APPROVAL_REQUIRED" })
    }

    @Test("status-only or tampered trust fails independent recomputation")
    func rejectsUnreproducibleTrust() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        let request = fixture.request(decisions: [ToolTrustDecision(
            toolID: fixture.toolID,
            status: .rejected,
            diagnostics: []
        )])

        let result = try await fixture.authorizer().execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_TOOL_TRUST_DECISION_MISMATCH" })
    }

    @Test("missing signoff axis fails closed")
    func rejectsIncompleteAxisCoverage() async throws {
        let fixture = try Fixture(includeAllAxes: false)
        defer { removeFixture(fixture.root) }

        let result = try await fixture.authorizer().execute(fixture.request())

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_BUNDLE_CONTENT_MISMATCH" })
    }

    @Test("approval must bind the exact run and release stage")
    func rejectsApprovalScopeMismatch() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let approval = FlowApprovalRecord(
            runID: "other-run",
            stageID: base.stageID,
            verdict: .approved,
            reviewer: "reviewer",
            reviewerKind: .human,
            createdAt: base.evaluatedAt,
            evidence: base.approval.evidence
        )

        let result = try await fixture.authorizer().execute(fixture.request(approval: approval))

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_APPROVAL_SCOPE_MISMATCH" })
    }

    @Test("a rejected human verdict cannot authorize release")
    func rejectsNegativeApprovalVerdict() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let approval = FlowApprovalRecord(
            runID: base.runID,
            stageID: base.stageID,
            verdict: .rejected,
            reviewer: "reviewer",
            reviewerKind: .human,
            createdAt: base.evaluatedAt,
            evidence: base.approval.evidence
        )

        let result = try await fixture.authorizer().execute(fixture.request(approval: approval))

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_APPROVAL_REJECTED" })
    }

    @Test("approval cannot be timestamped after authorization")
    func rejectsFutureApprovalTimestamp() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let approval = FlowApprovalRecord(
            runID: base.runID,
            stageID: base.stageID,
            verdict: .approved,
            reviewer: "reviewer",
            reviewerKind: .human,
            createdAt: base.evaluatedAt.addingTimeInterval(1),
            evidence: base.approval.evidence
        )

        let result = try await fixture.authorizer().execute(fixture.request(approval: approval))

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_APPROVAL_TIMESTAMP_INVALID" })
    }

    @Test("approval evidence must bind the exact signoff artifact")
    func rejectsApprovalEvidenceMismatch() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let approval = FlowApprovalRecord(
            runID: base.runID,
            stageID: base.stageID,
            verdict: .approved,
            reviewer: "reviewer",
            reviewerKind: .human,
            createdAt: base.evaluatedAt,
            evidence: FlowApprovalEvidenceBinding(plan: fixture.planArtifact, stageResult: fixture.planArtifact)
        )

        let result = try await fixture.authorizer().execute(fixture.request(approval: approval))

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_APPROVAL_EVIDENCE_MISMATCH" })
    }

    @Test("release must declare required tools")
    func rejectsEmptyRequiredToolSet() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let request = fixture.replacing(base, requiredToolIDs: [])

        let result = try await fixture.authorizer().execute(request)

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_REQUIRED_TOOLS_INVALID" })
    }

    @Test("duplicate retained trust decisions fail closed")
    func rejectsDuplicateTrustDecisions() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let request = fixture.replacing(base, decisions: [fixture.decision, fixture.decision])

        let result = try await fixture.authorizer().execute(request)

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_TOOL_TRUST_DUPLICATED" })
    }

    @Test("every required tool needs a retained decision and qualification request")
    func rejectsMissingRequiredToolTrust() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let request = fixture.replacing(base, requiredToolIDs: [fixture.toolID, "missing-tool"])

        let result = try await fixture.authorizer().execute(request)

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_TOOL_TRUST_MISSING" })
    }

    @Test("tool qualification cannot be newer than release authorization")
    func rejectsFutureQualificationTimestamp() async throws {
        let fixture = try Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let original = fixture.qualificationRequest
        let future = ToolQualificationRequest(
            descriptor: original.descriptor,
            requirement: original.requirement,
            health: original.health,
            inputs: original.inputs,
            evaluatedAt: base.evaluatedAt.addingTimeInterval(1)
        )
        let request = fixture.replacing(base, qualificationRequests: [future])

        let result = try await fixture.authorizer().execute(request)

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_TOOL_TRUST_TIMESTAMP_INVALID" })
    }
}

private struct Fixture {
    let root: URL
    let evaluatedAt = Date(timeIntervalSince1970: 10_000)
    let toolID = "release-test-tool"
    let bundleReference: SignoffBundleReference
    let planArtifact: ArtifactReference
    let qualificationRequest: ToolQualificationRequest
    let decision: ToolTrustDecision

    init(includeAllAxes: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "release-authorization-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bundle = SignoffBundle(
            bundleID: "bundle",
            profileID: "digital",
            designDigest: String(repeating: "a", count: 64),
            pdkDigest: String(repeating: "b", count: 64),
            finalLayoutDigest: String(repeating: "c", count: 64),
            axisResults: (includeAllAxes ? ReleaseSignoffAxis.allCases : Array(ReleaseSignoffAxis.allCases.dropLast())).map {
                SignoffAxisResult(axis: $0, disposition: .passed, evidenceIDs: ["evidence-\($0.rawValue)"], reason: "passed")
            },
            waivers: [],
            evidenceDigest: String(repeating: "d", count: 64),
            issuedAt: evaluatedAt
        )
        let bundleURL = root.appending(path: "signoff-bundle.json")
        try bundle.canonicalData().write(to: bundleURL, options: .atomic)
        let bundleArtifact = try Self.reference(
            path: "signoff-bundle.json",
            role: .output,
            kind: .release,
            root: root
        )
        bundleReference = SignoffBundleReference(
            artifact: bundleArtifact,
            designDigest: bundle.designDigest,
            pdkDigest: bundle.pdkDigest,
            finalLayoutDigest: bundle.finalLayoutDigest
        )

        try Data("plan".utf8).write(to: root.appending(path: "plan.json"), options: .atomic)
        planArtifact = try Self.reference(path: "plan.json", role: .input, kind: .request, root: root)

        let descriptor = ToolDescriptor(
            toolID: toolID,
            displayName: "Release test tool",
            kind: .reporting,
            version: "1.0.0",
            capabilities: [ToolCapability(operationID: "release.authorize")],
            trustProfile: ToolTrustProfile(level: .smokeChecked),
            environment: ToolEnvironment(platform: "macOS")
        )
        let requirement = ToolTrustRequirement(
            kind: .reporting,
            operationID: "release.authorize",
            minimumLevel: .smokeChecked,
            requirePassingHealthCheck: false
        )
        qualificationRequest = ToolQualificationRequest(
            descriptor: descriptor,
            requirement: requirement,
            evaluatedAt: evaluatedAt
        )
        decision = ToolTrustDecision(toolID: toolID, status: .eligible)
    }

    func request(
        approval suppliedApproval: FlowApprovalRecord? = nil,
        decisions: [ToolTrustDecision]? = nil
    ) -> ReleaseAuthorizationRequest {
        let approval = suppliedApproval ?? FlowApprovalRecord(
            runID: "run",
            stageID: "release",
            verdict: .approved,
            reviewer: "reviewer",
            reviewerKind: .human,
            createdAt: evaluatedAt,
            evidence: FlowApprovalEvidenceBinding(plan: planArtifact, stageResult: bundleReference.artifact)
        )
        return ReleaseAuthorizationRequest(
            runID: "run",
            stageID: "release",
            signoffBundle: bundleReference,
            approval: approval,
            toolTrustDecisions: decisions ?? [decision],
            toolQualificationRequests: [qualificationRequest],
            requiredToolIDs: [toolID],
            evaluatedAt: evaluatedAt
        )
    }

    func authorizer() throws -> DefaultReleaseAuthorizer {
        let qualificationReader = LocalToolQualificationArtifactReader(workspaceRoot: root)
        let qualificationEngine = DefaultToolQualificationEngine(
            artifactReader: qualificationReader,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "ToolQualification",
                version: "1.0.0"
            ),
            completionDate: { evaluatedAt }
        )
        return DefaultReleaseAuthorizer(
            qualificationEngine: qualificationEngine,
            artifactReader: LocalReleaseArtifactReader(workspaceRoot: root)
        )
    }

    func replacing(
        _ request: ReleaseAuthorizationRequest,
        decisions: [ToolTrustDecision]? = nil,
        qualificationRequests: [ToolQualificationRequest]? = nil,
        requiredToolIDs: [String]? = nil
    ) -> ReleaseAuthorizationRequest {
        ReleaseAuthorizationRequest(
            runID: request.runID,
            stageID: request.stageID,
            signoffBundle: request.signoffBundle,
            approval: request.approval,
            toolTrustDecisions: decisions ?? request.toolTrustDecisions,
            toolQualificationRequests: qualificationRequests ?? request.toolQualificationRequests,
            requiredToolIDs: requiredToolIDs ?? request.requiredToolIDs,
            evaluatedAt: request.evaluatedAt
        )
    }

    private static func reference(
        path: String,
        role: ArtifactRole,
        kind: ArtifactKind,
        root: URL
    ) throws -> ArtifactReference {
        try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: role,
                kind: kind,
                format: .json
            ),
            relativeTo: root
        )
    }
}

private func removeFixture(_ root: URL) {
    do {
        try FileManager.default.removeItem(at: root)
    } catch {
        Issue.record("Failed to remove release fixture: \(error.localizedDescription)")
    }
}
