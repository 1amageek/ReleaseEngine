import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore
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
        #expect(result.evidence.provenance.inputs.contains(
            fixture.planArtifact.reference
        ))
        #expect(result.evidence.provenance.inputs.contains(
            fixture.request().approval.evidence.stageResult.reference
        ))
        #expect(result.evidence.provenance.inputs.contains(
            fixture.bundleReference.artifact.reference
        ))
        #expect(result.evidence.provenance.inputs.contains(fixture.signoffEvidenceArtifact))
        #expect(Set(result.evidence.provenance.inputs).isSuperset(
            of: Set(fixture.qualificationRequest.inputs)
        ))
    }

    @Test("release approval identities must equal the builder-owned inventory")
    func rejectsApprovalIdentityInventoryDrift() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let exactBundle = ReleaseExactBundle(
            databaseRevisions: fixture.exactReleaseBundle.databaseRevisions,
            semanticDependencyGraphDigest: fixture.exactReleaseBundle
                .semanticDependencyGraphDigest,
            contentIdentities: fixture.exactReleaseBundle.contentIdentities,
            approvalContentIdentities: [fixture.signoffEvidenceArtifact.id],
            qualificationContentIdentities: fixture.exactReleaseBundle
                .qualificationContentIdentities,
            retentionReceipts: fixture.exactReleaseBundle.retentionReceipts
        )
        let request = fixture.replacing(
            fixture.request(),
            exactReleaseBundle: exactBundle
        )

        let result = try await fixture.authorizer().execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "RELEASE_APPROVAL_CONTENT_IDENTITY_MISMATCH"
        })
    }

    @Test("release qualification identities must equal the builder-owned inventory")
    func rejectsQualificationIdentityInventoryDrift() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let exactBundle = ReleaseExactBundle(
            databaseRevisions: fixture.exactReleaseBundle.databaseRevisions,
            semanticDependencyGraphDigest: fixture.exactReleaseBundle
                .semanticDependencyGraphDigest,
            contentIdentities: fixture.exactReleaseBundle.contentIdentities,
            approvalContentIdentities: fixture.exactReleaseBundle
                .approvalContentIdentities,
            qualificationContentIdentities: [fixture.planArtifact.reference.id],
            retentionReceipts: fixture.exactReleaseBundle.retentionReceipts
        )
        let request = fixture.replacing(
            fixture.request(),
            exactReleaseBundle: exactBundle
        )

        let result = try await fixture.authorizer().execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "RELEASE_QUALIFICATION_CONTENT_IDENTITY_MISMATCH"
        })
    }

    @Test("unclassified content identities cannot enter the exact release bundle")
    func rejectsUnclassifiedContentIdentity() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let unclassified = try ArtifactID(
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "0", count: 64)
            ),
            byteCount: 1
        )
        let exactBundle = ReleaseExactBundle(
            databaseRevisions: fixture.exactReleaseBundle.databaseRevisions,
            semanticDependencyGraphDigest: fixture.exactReleaseBundle
                .semanticDependencyGraphDigest,
            contentIdentities: fixture.exactReleaseBundle.contentIdentities
                + [unclassified],
            approvalContentIdentities: fixture.exactReleaseBundle
                .approvalContentIdentities,
            qualificationContentIdentities: fixture.exactReleaseBundle
                .qualificationContentIdentities,
            retentionReceipts: fixture.exactReleaseBundle.retentionReceipts
        )
        let request = fixture.replacing(
            fixture.request(),
            exactReleaseBundle: exactBundle
        )

        let result = try await fixture.authorizer().execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "RELEASE_CONTENT_IDENTITY_INVENTORY_MISMATCH"
        })
    }

    @Test("explicit additional content identities participate in exact authorization")
    func acceptsExplicitAdditionalContentIdentity() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let additional = try ArtifactID(
            digest: ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "0", count: 64)
            ),
            byteCount: 1
        )
        let exactBundle = ReleaseExactBundle(
            databaseRevisions: fixture.exactReleaseBundle.databaseRevisions,
            semanticDependencyGraphDigest: fixture.exactReleaseBundle
                .semanticDependencyGraphDigest,
            contentIdentities: fixture.exactReleaseBundle.contentIdentities
                + [additional],
            approvalContentIdentities: fixture.exactReleaseBundle
                .approvalContentIdentities,
            qualificationContentIdentities: fixture.exactReleaseBundle
                .qualificationContentIdentities,
            retentionReceipts: fixture.exactReleaseBundle.retentionReceipts
        )
        let request = fixture.replacing(
            fixture.request(),
            exactReleaseBundle: exactBundle,
            additionalContentIdentities: [additional]
        )

        let result = try await fixture.authorizer().execute(request)

        #expect(result.status == .authorized)
        #expect(result.exactReleaseBundle == exactBundle)
    }

    @Test("authorization decoding rejects status and payload drift")
    func decoderRejectsStatusPayloadDrift() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let result = try await fixture.authorizer().execute(fixture.request())
        let encoded = try JSONEncoder().encode(result)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["status"] = ReleaseAuthorizationStatus.blocked.rawValue
        let invalid = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: ReleaseAuthorizationResultValidationError
            .blockedPayloadPresent) {
            _ = try JSONDecoder().decode(
                ReleaseAuthorizationResult.self,
                from: invalid
            )
        }
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

        let result = try await fixture.authorizer(
            approvalAuthenticator: RejectingReleaseApprovalAuthenticator(
                error: .signoffBundleNotReviewed
            )
        ).execute(fixture.request())

        #expect(result.diagnostics.contains {
            $0.code.rawValue == "RELEASE_APPROVAL_AUTHENTICATION_FAILED"
        })
    }

    @Test("human approval plan evidence must retain verified bytes")
    func rejectsMissingApprovalPlanEvidence() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        try FileManager.default.removeItem(
            at: fixture.root.appending(
                path: try fixture.relativePath(for: fixture.planArtifact).stringValue
            )
        )

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

    @Test("qualification record decisions are independently reproduced")
    func rejectsForgedQualificationRecordDecision() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        let base = fixture.request()
        let originalFlowBinding = try #require(
            base.qualificationRecordArtifacts.first
        )
        guard case .local(_, let rootID, let relativePath) = originalFlowBinding.availability else {
            Issue.record("Expected a local qualification record fixture.")
            return
        }
        let recordURL = fixture.root.appending(path: relativePath.stringValue)
        let originalData = try Data(contentsOf: recordURL)
        var object = try #require(
            JSONSerialization.jsonObject(with: originalData) as? [String: Any]
        )
        var issuanceDecisions = try #require(
            object["issuanceDecisions"] as? [[String: Any]]
        )
        var issuance = try #require(issuanceDecisions.first)
        var decision = try #require(issuance["decision"] as? [String: Any])
        decision["diagnostics"] = [[
            "severity": "warning",
            "code": "FORGED_RECORD_DECISION",
            "message": "This diagnostic was not produced by qualification.",
        ]]
        issuance["decision"] = decision
        issuanceDecisions[0] = issuance
        object["issuanceDecisions"] = issuanceDecisions
        let forgedData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        try forgedData.write(to: recordURL, options: .atomic)
        let forgedReference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: forgedData),
            byteCount: UInt64(forgedData.count),
            descriptor: originalFlowBinding.reference.descriptor
        )
        let forgedReleaseBinding = try ReleaseArtifactBinding(
            logicalID: "qualification.record.forged",
            reference: forgedReference,
            availability: .local(
                artifactID: forgedReference.id,
                rootID: rootID,
                relativePath: relativePath
            )
        )
        let forgedFlowBinding = try FlowArtifactBinding(
            logicalID: originalFlowBinding.logicalID,
            reference: forgedReference,
            availability: forgedReleaseBinding.availability
        )
        let artifactBindings = base.artifactBindings.filter {
            $0.reference.id != originalFlowBinding.reference.id
        } + [forgedReleaseBinding]
        let exact = ReleaseExactBundle(
            databaseRevisions: base.exactReleaseBundle.databaseRevisions,
            semanticDependencyGraphDigest: base.exactReleaseBundle
                .semanticDependencyGraphDigest,
            contentIdentities: base.exactReleaseBundle.contentIdentities.map {
                $0 == originalFlowBinding.reference.id ? forgedReference.id : $0
            },
            approvalContentIdentities: base.exactReleaseBundle
                .approvalContentIdentities,
            qualificationContentIdentities: base.exactReleaseBundle
                .qualificationContentIdentities.map {
                    $0 == originalFlowBinding.reference.id ? forgedReference.id : $0
                },
            retentionReceipts: base.exactReleaseBundle.retentionReceipts
        )
        let request = ReleaseAuthorizationRequest(
            runID: base.runID,
            stageID: base.stageID,
            signoffBundle: base.signoffBundle,
            exactReleaseBundle: exact,
            approval: base.approval,
            approvalArtifacts: base.approvalArtifacts,
            qualificationRecordArtifacts: [forgedFlowBinding],
            artifactBindings: artifactBindings,
            additionalContentIdentities: base.additionalContentIdentities,
            toolTrustDecisions: base.toolTrustDecisions,
            toolQualificationRequests: base.toolQualificationRequests,
            requiredToolIDs: base.requiredToolIDs,
            evaluatedAt: base.evaluatedAt,
            projectRoot: base.projectRoot
        )

        let result = try await fixture.authorizer().execute(request)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "RELEASE_QUALIFICATION_RECORD_READ_FAILED"
        })
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
            descriptor: ArtifactDescriptor(
                role: originalArtifact.descriptor.role,
                kind: .other,
                format: originalArtifact.descriptor.format
            )
        )
        bundle.evidenceArtifacts.append(collidingArtifact)

        #expect(bundle.isReleaseReady == false)
        let invalidData = try bundle.canonicalData()
        #expect(throws: SignoffBundleCanonicalEncodingError.self) {
            try SignoffBundle.decodeCanonical(from: invalidData)
        }
    }

    @Test("signoff bundle requires axis evidence identifiers")
    func rejectsUnboundAxisEvidence() async throws {
        let fixture = try await Fixture()
        defer { removeFixture(fixture.root) }
        var missingEvidenceID = try fixture.loadBundle()
        missingEvidenceID.axisResults[0].evidenceIDs = []

        #expect(missingEvidenceID.isReleaseReady == false)
        #expect(throws: SignoffBundleCanonicalEncodingError.self) {
            try SignoffBundle.decodeCanonical(from: missingEvidenceID.canonicalData())
        }
    }
}

private struct Fixture {
    let root: URL
    let evaluatedAt = Date(timeIntervalSince1970: 10_000)
    let toolID = "release-test-tool"
    let bundleReference: SignoffBundleReference
    let bundleFlowArtifact: FlowArtifactBinding
    let planArtifact: FlowArtifactBinding
    let approvalArtifact: FlowArtifactBinding
    let qualificationRecordArtifact: FlowArtifactBinding
    let signoffEvidenceArtifact: ArtifactReference
    let qualificationRequest: ToolQualificationRequest
    let decision: ToolTrustDecision
    let exactReleaseBundle: ReleaseExactBundle
    let artifactBindingsByID: [ArtifactID: ReleaseArtifactBinding]

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
        var generatedBindings = productionTrust.artifactBindingsByID
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
            root: root,
            bindings: &generatedBindings
        )
        bundleReference = SignoffBundleReference(
            artifact: bundleArtifact,
            designDigest: bundle.designDigest,
            pdkDigest: bundle.pdkDigest,
            finalLayoutDigest: bundle.finalLayoutDigest
        )
        bundleFlowArtifact = try Self.flowBinding(
            bundleArtifact,
            logicalID: "signoff-stage-result"
        )

        try Data("plan".utf8).write(to: root.appending(path: "plan.json"), options: .atomic)
        let planReleaseBinding = try Self.reference(
            path: "plan.json",
            role: .input,
            kind: .request,
            root: root,
            bindings: &generatedBindings
        )
        planArtifact = try Self.flowBinding(
            planReleaseBinding,
            logicalID: "release-plan"
        )
        qualificationRequest = productionTrust.request
        decision = productionTrust.decision
        let approval = FlowApprovalRecord(
            runID: "run",
            stageID: "release",
            verdict: .approved,
            reviewer: "reviewer",
            reviewerKind: .human,
            createdAt: evaluatedAt,
            evidence: FlowApprovalEvidenceBinding(
                plan: planArtifact,
                stageResult: bundleFlowArtifact
            )
        )
        let approvalURL = root.appending(path: "approval.json")
        try JSONEncoder().encode(approval).write(to: approvalURL, options: .atomic)
        let approvalReleaseBinding = try Self.reference(
            path: "approval.json",
            role: .output,
            kind: .report,
            root: root,
            bindings: &generatedBindings
        )
        approvalArtifact = try Self.flowBinding(
            approvalReleaseBinding,
            logicalID: "release-approval-record"
        )
        qualificationRecordArtifact = try Self.flowBinding(
            productionTrust.qualificationRecordArtifact,
            logicalID: "release-qualification-record"
        )
        let databaseID = try DesignDatabaseID(high: 0, low: 1)
        let revision = DesignRevisionReference(
            databaseID: databaseID,
            revisionID: DesignRevisionID(high: 0, low: 1)
        )
        let retention = DesignRevisionRetentionReceipt(
            operation: DesignDatabaseOperationReference(
                databaseID: databaseID,
                authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
                    high: 0,
                    low: 1
                ),
                operationID: try DesignDatabaseOperationID(
                    rawValue: "release-fixture-retention"
                )
            ),
            claimID: try DesignRevisionRetentionID(rawValue: "release-fixture"),
            revision: revision,
            generation: 1,
            reachabilityGeneration: 1,
            state: .active,
            outcomeDigest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "e", count: 64)
            )
        )
        let exactBundleRequest = ReleaseExactBundleBuildRequest(
            databaseRevisions: [ReleaseDatabaseRevisionBinding(
                databaseRole: "design",
                revision: revision
            )],
            semanticDependencyGraphDigest: try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "d", count: 64)
            ),
            signoffBundle: bundle,
            signoffBundleReference: bundleReference,
            approval: approval,
            approvalArtifacts: [approvalArtifact],
            toolQualificationRequests: [productionTrust.request],
            qualificationRecordArtifacts: [qualificationRecordArtifact],
            retentionReceipts: [retention]
        )
        if includeAllAxes {
            exactReleaseBundle = try DefaultReleaseExactBundleBuilder().build(
                exactBundleRequest
            )
        } else {
            let inventory = ReleaseExactContentInventory(request: exactBundleRequest)
            exactReleaseBundle = ReleaseExactBundle(
                databaseRevisions: exactBundleRequest.databaseRevisions,
                semanticDependencyGraphDigest: exactBundleRequest
                    .semanticDependencyGraphDigest,
                contentIdentities: inventory.contentIdentities,
                approvalContentIdentities: inventory.approvalContentIdentities,
                qualificationContentIdentities: inventory
                    .qualificationContentIdentities,
                retentionReceipts: exactBundleRequest.retentionReceipts
            )
        }
        artifactBindingsByID = generatedBindings
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
            evidence: FlowApprovalEvidenceBinding(
                plan: planArtifact,
                stageResult: bundleFlowArtifact
            )
        )
        return ReleaseAuthorizationRequest(
            runID: "run",
            stageID: "release",
            signoffBundle: bundleReference,
            exactReleaseBundle: exactReleaseBundle,
            approval: approval,
            approvalArtifacts: [approvalArtifact],
            qualificationRecordArtifacts: [qualificationRecordArtifact],
            artifactBindings: artifactBindingsByID.values.sorted {
                $0.reference.id.description < $1.reference.id.description
            },
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
        let qualificationReader = TestToolQualificationArtifactReader(
            root: root,
            availabilities: artifactBindingsByID.mapValues(\.availability)
        )
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

    func relativePath(
        for artifact: FlowArtifactBinding
    ) throws -> ArtifactRelativePath {
        guard case .local(_, _, let relativePath) = artifact.availability else {
            throw ReleaseArtifactBindingError.missingBinding(
                artifact.reference.id
            )
        }
        return relativePath
    }

    func replacing(
        _ request: ReleaseAuthorizationRequest,
        exactReleaseBundle: ReleaseExactBundle? = nil,
        additionalContentIdentities: [ArtifactID]? = nil,
        decisions: [ToolTrustDecision]? = nil,
        qualificationRequests: [ToolQualificationRequest]? = nil,
        requiredToolIDs: [String]? = nil
    ) -> ReleaseAuthorizationRequest {
        ReleaseAuthorizationRequest(
            runID: request.runID,
            stageID: request.stageID,
            signoffBundle: request.signoffBundle,
            exactReleaseBundle: exactReleaseBundle ?? request.exactReleaseBundle,
            approval: request.approval,
            approvalArtifacts: request.approvalArtifacts,
            qualificationRecordArtifacts: request.qualificationRecordArtifacts,
            artifactBindings: request.artifactBindings,
            additionalContentIdentities: additionalContentIdentities
                ?? request.additionalContentIdentities,
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
        root: URL,
        bindings: inout [ArtifactID: ReleaseArtifactBinding]
    ) throws -> ReleaseArtifactBinding {
        let data = try Data(contentsOf: root.appending(path: path))
        let reference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            descriptor: ArtifactDescriptor(
                role: role,
                kind: kind,
                format: .json
            )
        )
        let binding = try ReleaseArtifactBinding(
            logicalID: path.replacingOccurrences(of: "/", with: "."),
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(
                    rawValue: "release-authorization-test-root"
                ),
                relativePath: ArtifactRelativePath(
                    segments: path.split(separator: "/").map(String.init)
                )
            )
        )
        bindings[reference.id] = binding
        return binding
    }

    private static func flowBinding(
        _ binding: ReleaseArtifactBinding,
        logicalID: String
    ) throws -> FlowArtifactBinding {
        try FlowArtifactBinding(
            logicalID: logicalID,
            reference: binding.reference,
            availability: binding.availability
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
    let qualificationRecordArtifact: ReleaseArtifactBinding
    let artifactBindingsByID: [ArtifactID: ReleaseArtifactBinding]

    init(root: URL, evaluatedAt: Date, toolID: String) async throws {
        var generatedBindings: [ArtifactID: ReleaseArtifactBinding] = [:]
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
        let tool = try Self.write(
            toolBytes, path: "qualification/tool", kind: .other,
            role: .input, root: root, bindings: &generatedBindings
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
            role: .input, root: root, bindings: &generatedBindings
        )
        let process = try Self.write(
            Data("process".utf8), path: "qualification/process.json", kind: .technology,
            role: .input, root: root, bindings: &generatedBindings
        )
        let pdk = try Self.write(
            Data("pdk".utf8), path: "qualification/pdk.json", kind: .technology,
            role: .input, root: root, bindings: &generatedBindings
        )
        let deck = try Self.write(
            Data("deck".utf8), path: "qualification/deck.json", kind: .ruleDeck,
            role: .input, root: root, bindings: &generatedBindings
        )
        let input = try Self.write(
            Data("input".utf8), path: "qualification/input.json", kind: .input,
            role: .input, root: root, bindings: &generatedBindings
        )
        designArtifact = input
        let output = try Self.write(
            Data("output".utf8), path: "qualification/output.json", kind: .report,
            role: .output, root: root, bindings: &generatedBindings
        )
        signoffEvidenceArtifact = output
        let oracleOutput = try Self.write(
            Data("oracle-output".utf8), path: "qualification/oracle-output.json", kind: .report,
            role: .output, root: root, bindings: &generatedBindings
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
            role: .output, root: root, bindings: &generatedBindings
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
            role: .output, root: root, bindings: &generatedBindings
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
            role: .output, root: root, bindings: &generatedBindings
        )
        let qualificationReader = TestToolQualificationArtifactReader(
            root: root,
            availabilities: generatedBindings.mapValues(\.availability)
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
            reading: qualificationReader,
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
        let healthCheck = ToolHealthCheckResult(
            toolID: toolID,
            status: .passed,
            evidence: evidence
        )
        request = ToolQualificationRequest(
            descriptor: descriptor,
            requirement: qualificationRequirement,
            health: healthCheck,
            inputs: processQualification.identityArtifacts.all
                + processQualification.evidenceArtifacts
                + processQualification.inputArtifacts
                + processQualification.outputArtifacts,
            evaluatedAt: evaluatedAt
        )
        let qualificationEngine = DefaultToolQualificationEngine(
            artifactReader: qualificationReader,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "ToolQualification",
                version: "1.0.0"
            ),
            completionDate: { evaluatedAt }
        )
        decision = try await qualificationEngine.execute(request).decision
        let qualificationRecord = try await DefaultToolQualificationRecordIssuer().issue(
            recordID: "release-production-record",
            descriptor: descriptor,
            health: healthCheck,
            issuer: issuer,
            reading: qualificationReader,
            issuedAt: evaluatedAt
        )
        let qualificationRecordReference = try Self.write(
            try qualificationRecord.canonicalData(),
            path: "qualification/record.json",
            kind: .evidence,
            role: .output,
            root: root,
            bindings: &generatedBindings
        )
        guard let retainedQualificationRecord = generatedBindings[
            qualificationRecordReference.id
        ] else {
            throw ReleaseArtifactBindingError.missingBinding(
                qualificationRecordReference.id
            )
        }
        qualificationRecordArtifact = retainedQualificationRecord
        artifactBindingsByID = generatedBindings
    }

    private static func write(
        _ data: Data,
        path: String,
        kind: ArtifactKind,
        role: ArtifactRole,
        root: URL,
        bindings: inout [ArtifactID: ReleaseArtifactBinding]
    ) throws -> ArtifactReference {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        let reference = try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: data),
            byteCount: UInt64(data.count),
            descriptor: ArtifactDescriptor(
                role: role,
                kind: kind,
                format: .json
            )
        )
        bindings[reference.id] = try ReleaseArtifactBinding(
            logicalID: path.replacingOccurrences(of: "/", with: "."),
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: ArtifactRootID(rawValue: "release-authorization-test-root"),
                relativePath: ArtifactRelativePath(
                    segments: path.split(separator: "/").map(String.init)
                )
            )
        )
        return reference
    }
}

private func removeFixture(_ root: URL) {
    do {
        try FileManager.default.removeItem(at: root)
    } catch {
        Issue.record("Failed to remove release fixture: \(error.localizedDescription)")
    }
}
