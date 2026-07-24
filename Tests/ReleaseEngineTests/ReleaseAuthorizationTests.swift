import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore
import ReleaseEngine
import SignoffEngine
import Testing
import ToolQualification

@Suite("Release authorization")
struct ReleaseAuthorizationTests {
    @Test("human approval and independently reproducible trust authorize an exact signoff bundle")
    func authorizesBoundInputs() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }

        let result = try await fixture.authorizer().execute(fixture.request())

        #expect(result.status == .authorized)
        #expect(result.signoffBundle == fixture.bundleReference)
        #expect(result.diagnostics.isEmpty)
        #expect(result.evidence.provenance.inputs.contains(fixture.planArtifact))
        #expect(result.evidence.provenance.inputs.contains(
            fixture.request().approval.evidence.stageResult
        ))
        #expect(result.evidence.provenance.inputs.contains(fixture.bundleReference.artifact))
        #expect(result.evidence.provenance.inputs.contains(fixture.signoffEvidenceArtifact))
        #expect(Set(result.evidence.provenance.inputs).isSuperset(
            of: Set(fixture.qualificationRequest.inputs)
        ))
    }

    @Test("signoff bundle must be produced by the canonical signoff engine")
    func rejectsSubstitutedSignoffBundleProducer() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let substitutedArtifact = ArtifactReference(
            id: base.signoffBundle.artifact.id,
            locator: base.signoffBundle.artifact.locator,
            digest: base.signoffBundle.artifact.digest,
            byteCount: base.signoffBundle.artifact.byteCount,
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "substituted-signoff",
                version: "2.0.0"
            )
        )
        let signoffBundle = SignoffBundleReference(
            artifact: substitutedArtifact,
            designDigest: base.signoffBundle.designDigest,
            designProvenance: base.signoffBundle.designProvenance,
            pdkDigest: base.signoffBundle.pdkDigest,
            finalLayoutDigest: base.signoffBundle.finalLayoutDigest
        )
        let approval = FlowApprovalRecord(
            runID: base.approval.runID,
            stageID: base.approval.stageID,
            verdict: base.approval.verdict,
            reviewer: base.approval.reviewer,
            reviewerKind: base.approval.reviewerKind,
            createdAt: base.approval.createdAt,
            evidence: FlowApprovalEvidenceBinding(
                plan: base.approval.evidence.plan,
                stageResult: substitutedArtifact
            )
        )
        let request = ReleaseAuthorizationRequest(
            runID: base.runID,
            stageID: base.stageID,
            signoffBundle: signoffBundle,
            approval: approval,
            toolTrustDecisions: base.toolTrustDecisions,
            toolQualificationRequests: base.toolQualificationRequests,
            requiredToolIDs: base.requiredToolIDs,
            evaluatedAt: base.evaluatedAt,
            projectRoot: base.projectRoot
        )

        let result = try await fixture.authorizer().execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_BUNDLE_CONTENT_MISMATCH" })
    }

    @Test("agent approval fails closed")
    func rejectsAgentApproval() async throws {
        let fixture = try await Fixture()
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
        let fixture = try await Fixture()
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
        let fixture = try await Fixture(includeAllAxes: false)
        defer { removeFixture(fixture.root) }

        let result = try await fixture.authorizer().execute(fixture.request())

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_BUNDLE_READ_FAILED" })
    }

    @Test("approval must bind the exact run and release stage")
    func rejectsApprovalScopeMismatch() async throws {
        let fixture = try await Fixture()
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

        let runMismatch = try await fixture.authorizer().execute(fixture.request(approval: approval))

        #expect(runMismatch.diagnostics.contains {
            $0.code.rawValue == "RELEASE_APPROVAL_SCOPE_MISMATCH"
        })

        let stageMismatch = FlowApprovalRecord(
            runID: base.runID,
            stageID: "other-release-stage",
            verdict: .approved,
            reviewer: "reviewer",
            reviewerKind: .human,
            createdAt: base.evaluatedAt,
            evidence: base.approval.evidence
        )
        let stageMismatchResult = try await fixture.authorizer().execute(
            fixture.request(approval: stageMismatch)
        )

        #expect(stageMismatchResult.diagnostics.contains {
            $0.code.rawValue == "RELEASE_APPROVAL_SCOPE_MISMATCH"
        })
    }

    @Test("a rejected human verdict cannot authorize release")
    func rejectsNegativeApprovalVerdict() async throws {
        let fixture = try await Fixture()
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
        let fixture = try await Fixture()
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

    @Test("approval authentication must prove the exact reviewed signoff artifact")
    func rejectsApprovalEvidenceMismatch() async throws {
        let fixture = try await Fixture()
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

        let result = try await fixture.authorizer(
            approvalAuthenticator: RejectingReleaseApprovalAuthenticator(
                error: .signoffBundleNotReviewed
            )
        ).execute(fixture.request(approval: approval))

        #expect(result.diagnostics.contains {
            $0.code.rawValue == "RELEASE_APPROVAL_AUTHENTICATION_FAILED"
        })
    }

    @Test("human approval plan evidence must retain verified bytes")
    func rejectsMissingApprovalPlanEvidence() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        try FileManager.default.removeItem(at: fixture.root.appending(path: fixture.planArtifact.path))

        let result = try await fixture.authorizer().execute(fixture.request())

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "RELEASE_APPROVAL_PLAN_EVIDENCE_FAILED"
        })
    }

    @Test("release must declare required tools")
    func rejectsEmptyRequiredToolSet() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let request = fixture.replacing(base, requiredToolIDs: [])

        let result = try await fixture.authorizer().execute(request)

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_REQUIRED_TOOLS_MISMATCH" })
    }

    @Test("duplicate retained trust decisions fail closed")
    func rejectsDuplicateTrustDecisions() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let request = fixture.replacing(base, decisions: [fixture.decision, fixture.decision])

        let result = try await fixture.authorizer().execute(request)

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_TOOL_TRUST_INVENTORY_MISMATCH" })
    }

    @Test("every required tool needs a retained decision and qualification request")
    func rejectsMissingRequiredToolTrust() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let request = fixture.replacing(base, requiredToolIDs: [fixture.toolID, "missing-tool"])

        let result = try await fixture.authorizer().execute(request)

        #expect(result.diagnostics.contains { $0.code.rawValue == "RELEASE_REQUIRED_TOOLS_MISMATCH" })
    }

    @Test("release authorization rejects a trust request below production eligibility")
    func rejectsNonProductionTrustRequirement() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let original = fixture.qualificationRequest
        let lowered = ToolQualificationRequest(
            descriptor: original.descriptor,
            requirement: ToolTrustRequirement(
                kind: original.requirement.kind,
                operationID: original.requirement.operationID,
                minimumLevel: .smokeChecked,
                qualificationScope: original.requirement.qualificationScope,
                requireIndependentQualificationEvidence: true
            ),
            health: original.health,
            inputs: original.inputs,
            evaluatedAt: original.evaluatedAt
        )

        let result = try await fixture.authorizer().execute(
            fixture.replacing(base, qualificationRequests: [lowered])
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "RELEASE_PRODUCTION_QUALIFICATION_REQUIRED"
        })
    }

    @Test("tool qualification cannot be newer than release authorization")
    func rejectsFutureQualificationTimestamp() async throws {
        let fixture = try await Fixture()
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

    @Test("canonical signoff bundle rejects non-normalized qualification scope order")
    func rejectsNonCanonicalQualificationScopeOrder() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        var bundle = try fixture.loadBundle()
        let originalScope = try #require(bundle.toolQualificationScopes.first)
        let originalOracle = try #require(originalScope.oracle)
        var precedingScope = originalScope
        precedingScope.oracle = ToolOracleQualificationScope(
            implementationID: "aaa-release-oracle",
            version: originalOracle.version,
            binaryDigest: originalOracle.binaryDigest
        )
        bundle.toolQualificationScopes = [originalScope, precedingScope]

        let nonCanonicalData = try bundle.canonicalData()

        #expect(throws: SignoffBundleCanonicalEncodingError.self) {
            try SignoffBundle.decodeCanonical(from: nonCanonicalData)
        }
    }

    @Test("signoff bundle rejects artifact identifier collisions")
    func rejectsArtifactIdentifierCollision() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        var bundle = try fixture.loadBundle()
        let originalArtifact = try #require(bundle.evidenceArtifacts.first)
        let collidingArtifact = ArtifactReference(
            id: originalArtifact.id,
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "qualification/collision.json"),
                role: originalArtifact.locator.role,
                kind: originalArtifact.kind,
                format: originalArtifact.format
            ),
            digest: originalArtifact.digest,
            byteCount: originalArtifact.byteCount,
            producer: originalArtifact.producer
        )
        bundle.evidenceArtifacts.append(collidingArtifact)

        #expect(bundle.isReleaseReady == false)
        let invalidData = try bundle.canonicalData()
        #expect(throws: SignoffBundleCanonicalEncodingError.self) {
            try SignoffBundle.decodeCanonical(from: invalidData)
        }
    }

    @Test("signoff bundle requires axis evidence identifiers and artifact producers")
    func rejectsUnboundAxisEvidence() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        var missingEvidenceID = try fixture.loadBundle()
        missingEvidenceID.axisResults[0].evidenceIDs = []

        #expect(missingEvidenceID.isReleaseReady == false)
        #expect(throws: SignoffBundleCanonicalEncodingError.self) {
            try SignoffBundle.decodeCanonical(from: missingEvidenceID.canonicalData())
        }

        var missingProducer = try fixture.loadBundle()
        let artifact = try #require(missingProducer.evidenceArtifacts.first)
        missingProducer.evidenceArtifacts[0] = ArtifactReference(
            id: artifact.id,
            locator: artifact.locator,
            digest: artifact.digest,
            byteCount: artifact.byteCount
        )
        #expect(missingProducer.isReleaseReady == false)
        #expect(throws: SignoffBundleCanonicalEncodingError.self) {
            try SignoffBundle.decodeCanonical(from: missingProducer.canonicalData())
        }
    }
}

private struct Fixture {
    let root: URL
    let evaluatedAt = Date(timeIntervalSince1970: 10_000)
    let toolID = "release-test-tool"
    let bundleReference: SignoffBundleReference
    let planArtifact: ArtifactReference
    let signoffEvidenceArtifact: ArtifactReference
    let qualificationRequest: ToolQualificationRequest
    let decision: ToolTrustDecision

    init(includeAllAxes: Bool = true) async throws {
        let fixtureToolID = "release-test-tool"
        root = FileManager.default.temporaryDirectory
            .appending(path: "release-authorization-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let productionTrust = try await ProductionTrustFixture(
            root: root,
            evaluatedAt: evaluatedAt,
            toolID: fixtureToolID
        )
        signoffEvidenceArtifact = productionTrust.signoffEvidenceArtifact
        let evidenceRecords = ReleaseSignoffAxis.allCases.map { axis in
            ReleaseSignoffEvidenceReference(
                evidenceID: "evidence-\(axis.rawValue)",
                axis: axis,
                artifact: productionTrust.signoffEvidenceArtifact,
                designDigest: productionTrust.designArtifact.digest.hexadecimalValue,
                pdkDigest: productionTrust.pdkDigest,
                toolID: fixtureToolID,
                toolVersion: productionTrust.scope.toolVersion,
                toolBinaryDigest: productionTrust.scope.binaryDigest,
                inputArtifacts: productionTrust.executionProvenance.inputs,
                executionProvenance: productionTrust.executionProvenance,
                processQualification: productionTrust.processQualification,
                disposition: .passed
            )
        }
        let bundle = SignoffBundle(
            bundleID: "bundle",
            profileID: "digital",
            designDigest: productionTrust.designArtifact.digest.hexadecimalValue,
            pdkDigest: productionTrust.pdkDigest,
            finalLayoutDigest: String(repeating: "c", count: 64),
            axisResults: (includeAllAxes ? ReleaseSignoffAxis.allCases : Array(ReleaseSignoffAxis.allCases.dropLast())).map {
                SignoffAxisResult(axis: $0, disposition: .passed, evidenceIDs: ["evidence-\($0.rawValue)"], reason: "passed")
            },
            waivers: [],
            evidenceRecords: includeAllAxes
                ? evidenceRecords
                : Array(evidenceRecords.dropLast()),
            evidenceArtifacts: [productionTrust.signoffEvidenceArtifact],
            toolQualificationScopes: [productionTrust.scope],
            evidenceDigest: try CanonicalSignoffEvidenceDigester().digest(
                includeAllAxes ? evidenceRecords : Array(evidenceRecords.dropLast())
            ),
            issuedAt: evaluatedAt
        )
        let bundleURL = root.appending(path: "signoff-bundle.json")
        try bundle.canonicalData().write(to: bundleURL, options: .atomic)
        let bundleArtifact = try Self.reference(
            path: "signoff-bundle.json",
            role: .output,
            kind: .release,
            producer: ProducerIdentity(
                kind: .engine,
                identifier: "native.release.signoff",
                version: "2.0.0",
                build: String(repeating: "a", count: 64)
            ),
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
        qualificationRequest = productionTrust.request
        decision = productionTrust.decision
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
            evaluatedAt: evaluatedAt,
            projectRoot: root.path
        )
    }

    func authorizer(
        approvalAuthenticator: any ReleaseApprovalAuthenticating =
            AcceptingReleaseApprovalAuthenticator()
    ) throws -> DefaultReleaseAuthorizer {
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
            artifactReader: LocalReleaseArtifactReader(workspaceRoot: root),
            approvalAuthenticator: approvalAuthenticator
        )
    }

    func loadBundle() throws -> SignoffBundle {
        let data = try Data(contentsOf: root.appending(path: "signoff-bundle.json"))
        return try SignoffBundle.decodeCanonical(from: data)
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
            evaluatedAt: request.evaluatedAt,
            projectRoot: request.projectRoot
        )
    }

    private static func reference(
        path: String,
        role: ArtifactRole,
        kind: ArtifactKind,
        producer: ProducerIdentity? = nil,
        root: URL
    ) throws -> ArtifactReference {
        try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: role,
                kind: kind,
                format: .json
            ),
            relativeTo: root,
            producer: producer
        )
    }
}

private struct AcceptingReleaseApprovalAuthenticator: ReleaseApprovalAuthenticating {
    func authenticate(
        approval: FlowApprovalRecord,
        runID: String,
        signoffBundle: ArtifactReference,
        evaluatedAt: Date
    ) async throws {}
}

private struct RejectingReleaseApprovalAuthenticator: ReleaseApprovalAuthenticating {
    let error: ReleaseApprovalAuthenticationError

    func authenticate(
        approval: FlowApprovalRecord,
        runID: String,
        signoffBundle: ArtifactReference,
        evaluatedAt: Date
    ) async throws {
        throw error
    }
}

struct ProductionTrustFixture {
    let scope: ToolQualificationScope
    let pdkDigest: String
    let designArtifact: ArtifactReference
    let signoffEvidenceArtifact: ArtifactReference
    let processQualification: ToolProcessQualificationEvidence
    let executableArtifact: ArtifactReference
    let executionProvenance: ExecutionProvenance
    let request: ToolQualificationRequest
    let decision: ToolTrustDecision

    init(root: URL, evaluatedAt: Date, toolID: String) async throws {
        let toolBytes = Data("""
        #!/bin/sh
        report=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--report" ]; then
            report="$2"
            shift 2
          else
            shift
          fi
        done
        printf '{"differenceAreaSquareMicrometers":0,"differenceCount":0,"schemaVersion":1}' > "$report"
        """.utf8)
        let toolDigest = try SHA256ContentDigester().digest(data: toolBytes)
        let toolProducer = try ProducerIdentity(
            kind: .tool,
            identifier: toolID,
            version: "1.0.0",
            build: toolDigest.hexadecimalValue
        )
        let oracleProducer = try ProducerIdentity(
            kind: .tool,
            identifier: "\(toolID)-oracle",
            version: "2.0.0"
        )
        let issuer = try ProducerIdentity(
            kind: .engine,
            identifier: "release-test-qualification-runner",
            version: "1.0.0"
        )
        let sourceProducer = try ProducerIdentity(
            kind: .library,
            identifier: "release-test-qualified-inputs",
            version: "1.0.0"
        )
        let tool = try Self.write(
            toolBytes, path: "qualification/tool", kind: .other,
            role: .input, producer: toolProducer, root: root
        )
        executableArtifact = tool
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: root.appending(path: "qualification/tool").path
        )
        let operationalToolProducer = try ProducerIdentity(
            kind: .tool,
            identifier: toolID,
            version: "1.0.0",
            build: tool.digest.hexadecimalValue
        )
        let oracle = try Self.write(
            Data("oracle".utf8), path: "qualification/oracle-tool", kind: .other,
            role: .input, producer: oracleProducer, root: root
        )
        let process = try Self.write(
            Data("process".utf8), path: "qualification/process.json", kind: .technology,
            role: .input, producer: sourceProducer, root: root
        )
        let pdk = try Self.write(
            Data("pdk".utf8), path: "qualification/pdk.json", kind: .technology,
            role: .input, producer: sourceProducer, root: root
        )
        let deck = try Self.write(
            Data("deck".utf8), path: "qualification/deck.json", kind: .ruleDeck,
            role: .input, producer: sourceProducer, root: root
        )
        let input = try Self.write(
            Data("input".utf8), path: "qualification/input.json", kind: .input,
            role: .input, producer: sourceProducer, root: root
        )
        designArtifact = input
        let output = try Self.write(
            Data("output".utf8), path: "qualification/output.json", kind: .report,
            role: .output, producer: operationalToolProducer, root: root
        )
        signoffEvidenceArtifact = output
        let oracleOutput = try Self.write(
            Data("oracle-output".utf8), path: "qualification/oracle-output.json", kind: .report,
            role: .output, producer: oracleProducer, root: root
        )
        scope = ToolQualificationScope(
            implementationID: toolID,
            toolVersion: toolProducer.version,
            binaryDigest: tool.digest.hexadecimalValue,
            algorithmVersion: "release-v1",
            processProfileID: "release-process",
            processProfileDigest: process.digest.hexadecimalValue,
            deckDigest: deck.digest.hexadecimalValue,
            pdkID: "release-pdk",
            pdkDigest: pdk.digest.hexadecimalValue,
            oracle: ToolOracleQualificationScope(
                implementationID: oracleProducer.identifier,
                version: oracleProducer.version,
                binaryDigest: oracle.digest.hexadecimalValue
            )
        )
        pdkDigest = pdk.digest.hexadecimalValue
        let outcome = ToolQualificationCaseOutcome(
            caseID: "release-case",
            coverageTags: ["release"],
            comparisons: [
                ToolQualificationMetricComparison(
                    metricID: "failure-count",
                    observed: 0,
                    expected: 0
                )
            ]
        )
        let corpus = ToolCorpusQualificationResult(
            resultID: "release-corpus",
            qualificationID: "release-production",
            toolID: toolID,
            scope: scope,
            issuer: issuer,
            inputArtifacts: [input, pdk],
            outputArtifacts: [output],
            cases: [outcome],
            checkedAt: evaluatedAt
        )
        let corpusArtifact = try Self.write(
            try corpus.canonicalData(), path: "qualification/corpus.json", kind: .evidence,
            role: .output, producer: issuer, root: root
        )
        let oracleResult = ToolOracleQualificationResult(
            resultID: "release-oracle",
            qualificationID: "release-production",
            primaryToolID: toolID,
            oracleToolID: oracleProducer.identifier,
            scope: scope,
            issuer: issuer,
            inputArtifacts: [input, pdk],
            primaryOutputArtifacts: [output],
            oracleOutputArtifacts: [oracleOutput],
            cases: [
                ToolOracleCaseComparison(
                    caseID: outcome.caseID,
                    primary: outcome,
                    oracle: outcome,
                    agreementComparisons: [
                        ToolOracleMetricComparison(
                            metricID: "failure-count",
                            primaryObserved: 0,
                            oracleObserved: 0
                        )
                    ]
                )
            ],
            checkedAt: evaluatedAt
        )
        let oracleArtifact = try Self.write(
            try oracleResult.canonicalData(), path: "qualification/oracle.json", kind: .evidence,
            role: .output, producer: issuer, root: root
        )
        let health = ToolHealthQualificationResult(
            resultID: "release-health",
            qualificationID: "release-production",
            toolID: toolID,
            scope: scope,
            issuer: issuer,
            inputArtifacts: [input, pdk],
            outputArtifacts: [output],
            checkedAt: evaluatedAt
        )
        let healthArtifact = try Self.write(
            try health.canonicalData(), path: "qualification/health.json", kind: .evidence,
            role: .output, producer: issuer, root: root
        )
        processQualification = try await ToolProcessQualificationEvidenceBuilder().build(
            ToolProcessQualificationEvidenceBuildRequest(
                qualificationID: "release-production",
                toolID: toolID,
                scope: scope,
                identityArtifacts: ToolProcessQualificationArtifacts(
                    toolExecutable: tool,
                    processProfile: process,
                    pdk: pdk,
                    ruleDeck: deck,
                    oracleExecutable: oracle
                ),
                corpusResultArtifacts: [corpusArtifact],
                oracleResultArtifacts: [oracleArtifact],
                healthResultArtifacts: [healthArtifact],
                inputArtifacts: [input, pdk],
                outputArtifacts: [output, oracleOutput],
                qualifiedAt: evaluatedAt.addingTimeInterval(-10),
                expiresAt: evaluatedAt.addingTimeInterval(10)
            ),
            reading: LocalToolQualificationArtifactReader(workspaceRoot: root),
            at: evaluatedAt
        )
        executionProvenance = try ExecutionProvenance(
            producer: operationalToolProducer,
            inputs: [input, pdk],
            startedAt: evaluatedAt.addingTimeInterval(-2),
            completedAt: evaluatedAt.addingTimeInterval(-1)
        )
        let evidence = [
            ToolEvidence(
                evidenceID: corpus.resultID,
                kind: .corpus,
                artifact: corpusArtifact,
                checkedAt: evaluatedAt
            ),
            ToolEvidence(
                evidenceID: oracleResult.resultID,
                kind: .oracle,
                artifact: oracleArtifact,
                checkedAt: evaluatedAt
            ),
            ToolEvidence(
                evidenceID: health.resultID,
                kind: .healthCheck,
                artifact: healthArtifact,
                checkedAt: evaluatedAt
            ),
        ]
        let descriptor = ToolDescriptor(
            toolID: toolID,
            displayName: "Release test tool",
            kind: .reporting,
            version: toolProducer.version,
            capabilities: [ToolCapability(operationID: "release.authorize")],
            trustProfile: ToolTrustProfile(
                level: .productionEligible,
                evidence: evidence,
                processQualification: processQualification
            ),
            environment: ToolEnvironment(platform: "macOS")
        )
        let qualificationRequirement = ToolTrustRequirement(
            kind: .reporting,
            operationID: "release.authorize",
            minimumLevel: .productionEligible,
            requirePassingHealthCheck: false,
            qualificationScope: scope,
            requireIndependentQualificationEvidence: true
        )
        request = ToolQualificationRequest(
            descriptor: descriptor,
            requirement: qualificationRequirement,
            inputs: processQualification.identityArtifacts.all
                + processQualification.evidenceArtifacts
                + processQualification.inputArtifacts
                + processQualification.outputArtifacts,
            evaluatedAt: evaluatedAt
        )
        let qualificationEngine = DefaultToolQualificationEngine(
            artifactReader: LocalToolQualificationArtifactReader(workspaceRoot: root),
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "ToolQualification",
                version: "1.0.0"
            ),
            completionDate: { evaluatedAt }
        )
        decision = try await qualificationEngine.execute(request).decision
    }

    private static func write(
        _ data: Data,
        path: String,
        kind: ArtifactKind,
        role: ArtifactRole,
        producer: ProducerIdentity? = nil,
        root: URL
    ) throws -> ArtifactReference {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        return try LocalArtifactReferencer().reference(
            ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: role,
                kind: kind,
                format: .json
            ),
            relativeTo: root,
            producer: producer
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
