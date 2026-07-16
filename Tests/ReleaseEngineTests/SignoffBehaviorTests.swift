import CircuiteFoundation
import Foundation
import LogicIR
import ReleaseCore
import SignoffEngine
import Testing
import ToolQualification

@Suite("Signoff behavior")
struct SignoffBehaviorTests {
    @Test("built-in profiles require every production axis")
    func builtInProfiles() {
        let provider = DefaultSignoffProfileProvider()
        for profileID in ["digital", "analog", "mixed-signal"] {
            let profile = provider.profile(profileID: profileID)
            #expect(profile?.requirements.count == ReleaseSignoffAxis.allCases.count)
            #expect(profile?.requirements.allSatisfy { $0.required && $0.minimumQualificationLevel == .productionEligible } == true)
        }
    }

    @Test("missing typed evidence blocks signoff")
    func missingEvidenceBlocks() async throws {
        let request = SignoffRequest(
            runID: "missing",
            inputs: [],
            profileID: "digital",
            designDigest: String(repeating: "1", count: 64),
            pdkDigest: String(repeating: "2", count: 64),
            evidence: []
        )
        let result = try await DefaultSignoffEvaluator().execute(request)
        #expect(result.status == .blocked)
        #expect(!result.payload.passed)
        #expect(result.diagnostics.contains { $0.code.rawValue == "EVIDENCE_RECORDS_REQUIRED" })
    }

    @Test("invalid design lineage blocks signoff")
    func invalidLineageBlocks() async throws {
        let digest = String(repeating: "1", count: 64)
        let request = SignoffRequest(
            runID: "lineage",
            inputs: [],
            profileID: "digital",
            designDigest: digest,
            designProvenance: LogicDesignProvenance(
                sourceDesignDigest: digest,
                inputDesignDigest: String(repeating: "9", count: 64),
                transformationID: "mapped",
                producerID: "test",
                producerVersion: "1"
            ),
            pdkDigest: String(repeating: "2", count: 64),
            evidence: []
        )
        let result = try await DefaultSignoffEvaluator().execute(request)
        #expect(result.status == .blocked)
        #expect(result.payload.blockedAxes.contains("provenance"))
        #expect(result.diagnostics.contains { $0.code.rawValue == "DESIGN_PROVENANCE_INPUT_DIGEST_MISMATCH" })
    }

    @Test("complete retained evidence reproduces one immutable canonical bundle")
    func completeBundle() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        let result = try await fixture.evaluate()
        #expect(result.status == .completed)
        #expect(result.payload.passed)
        #expect(result.payload.bundle == fixture.bundleReference)
        #expect(result.payload.axisResults.count == ReleaseSignoffAxis.allCases.count)
        #expect(result.payload.axisResults.allSatisfy { $0.disposition == .passed })
    }

    @Test("expired waiver cannot convert a failed axis")
    func invalidWaiverBlocks() async throws {
        let fixture = try await SignoffFixture(failedAxis: .simulation)
        defer { removeReleaseFixture(fixture.root) }
        let old = Date(timeIntervalSince1970: 100)
        let waiver = SignoffWaiver(
            waiverID: "expired",
            axis: .simulation,
            reason: "expired exception",
            authority: "review-board",
            approvedAt: old,
            expiresAt: old.addingTimeInterval(1),
            affectedEvidenceIDs: ["evidence-simulation"],
            designDigest: fixture.designDigest,
            pdkDigest: fixture.pdkDigest
        )
        let result = try await fixture.evaluate(waivers: [waiver])
        #expect(result.status == .blocked)
        #expect(!result.payload.passed)
        #expect(result.diagnostics.contains { $0.code.rawValue == "WAIVER_EXPIRED_OR_INVALID" })
    }

    @Test("unknown signoff profiles fail closed")
    func unknownProfileBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }

        let result = try await fixture.evaluate(profileID: "unknown-profile")

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "SIGNOFF_PROFILE_NOT_FOUND" })
    }

    @Test("profile and design kind must agree")
    func designKindMismatchBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }

        let result = try await fixture.evaluate(designKind: .analog)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "SIGNOFF_PROFILE_DESIGN_KIND_MISMATCH" })
    }

    @Test("every required axis retains typed evidence")
    func missingAxisEvidenceBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }

        let result = try await fixture.evaluate(records: Array(fixture.records.dropLast()))

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "REQUIRED_EVIDENCE_MISSING" })
    }

    @Test("evidence identities are unique within a signoff request")
    func duplicateEvidenceIdentityBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        let duplicate = try #require(fixture.records.first)

        let result = try await fixture.evaluate(records: fixture.records + [duplicate])

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "DUPLICATE_EVIDENCE_ID" })
    }

    @Test("evidence must bind the exact design revision")
    func designDigestMismatchBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        records[0].designDigest = String(repeating: "9", count: 64)

        let result = try await fixture.evaluate(records: records)

        #expect(result.diagnostics.contains { $0.code.rawValue == "DESIGN_DIGEST_MISMATCH" })
    }

    @Test("evidence must bind the exact PDK revision")
    func pdkDigestMismatchBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        records[0].pdkDigest = String(repeating: "9", count: 64)

        let result = try await fixture.evaluate(records: records)

        #expect(result.diagnostics.contains { $0.code.rawValue == "PDK_DIGEST_MISMATCH" })
    }

    @Test("evidence must identify the producing tool")
    func missingToolIdentityBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        records[0].toolID = " "

        let result = try await fixture.evaluate(records: records)

        #expect(result.diagnostics.contains { $0.code.rawValue == "TOOL_IDENTITY_REQUIRED" })
    }

    @Test("signoff evidence retains immutable design and PDK inputs")
    func incompleteInputBindingBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        records[0].inputArtifacts = [fixture.designArtifact]

        let result = try await fixture.evaluate(records: records)

        #expect(result.diagnostics.contains { $0.code.rawValue == "SIGNOFF_INPUT_BINDING_INCOMPLETE" })
    }

    @Test("artifact verification requires a project root")
    func missingProjectRootBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }

        let result = try await fixture.evaluate(includeProjectRoot: false)

        #expect(result.diagnostics.contains { $0.code.rawValue == "EVIDENCE_PROJECT_ROOT_REQUIRED" })
    }

    @Test("an unwaived failed axis remains failed")
    func failedEvidenceCannotPassSignoff() async throws {
        let fixture = try await SignoffFixture(failedAxis: .simulation)
        defer { removeReleaseFixture(fixture.root) }

        let result = try await fixture.evaluate()

        #expect(result.status == .failed)
        #expect(result.payload.axisResults.contains { $0.axis == .simulation && $0.disposition == .failed })
        #expect(!result.payload.passed)
    }

    @Test("artifact bytes cannot change after evidence is referenced")
    func tamperedEvidenceArtifactBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        let record = try #require(fixture.records.first)
        try Data("tampered".utf8).write(
            to: fixture.root.appending(path: record.artifact.path),
            options: .atomic
        )

        let result = try await fixture.evaluate()

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "EVIDENCE_ARTIFACT_INTEGRITY_FAILED" })
    }
}

private struct SignoffFixture {
    let root: URL
    let evaluatedAt = Date(timeIntervalSince1970: 1_000)
    let issuedAt = Date(timeIntervalSince1970: 999)
    let designArtifact: ArtifactReference
    let pdkArtifact: ArtifactReference
    let designDigest: String
    let pdkDigest: String
    let records: [ReleaseSignoffEvidenceReference]
    let bundleReference: SignoffBundleReference

    init(failedAxis: ReleaseSignoffAxis? = nil) async throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "signoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        designArtifact = try Self.write("design", path: "inputs/design.json", kind: .input, role: .input, root: root)
        pdkArtifact = try Self.write("pdk", path: "inputs/pdk.json", kind: .technology, role: .input, root: root)
        let localDesignDigest = designArtifact.sha256
        let localPDKDigest = pdkArtifact.sha256
        designDigest = localDesignDigest
        pdkDigest = localPDKDigest

        let toolProducer = try ProducerIdentity(kind: .tool, identifier: "signoff-tool", version: "1.0.0")
        let oracleProducer = try ProducerIdentity(kind: .tool, identifier: "signoff-oracle", version: "2.0.0")
        let issuer = try ProducerIdentity(kind: .engine, identifier: "qualification-engine", version: "1.0.0")
        let tool = try Self.write("tool", path: "identity/tool", kind: .other, role: .input, root: root, producer: toolProducer)
        let process = try Self.write("process", path: "identity/process.json", kind: .technology, role: .input, root: root)
        let pdk = pdkArtifact
        let deck = try Self.write("deck", path: "identity/deck.json", kind: .ruleDeck, role: .input, root: root)
        let oracle = try Self.write("oracle", path: "identity/oracle", kind: .other, role: .input, root: root, producer: oracleProducer)
        let scope = ToolQualificationScope(
            implementationID: "signoff-tool",
            toolVersion: "1.0.0",
            binaryDigest: tool.sha256,
            algorithmVersion: "signoff-v1",
            processProfileID: "process",
            processProfileDigest: process.sha256,
            deckDigest: deck.sha256,
            pdkID: "pdk",
            pdkDigest: pdk.sha256,
            oracle: ToolOracleQualificationScope(
                implementationID: "signoff-oracle",
                version: "2.0.0",
                binaryDigest: oracle.sha256
            )
        )
        var reports: [ArtifactReference] = []
        for axis in ReleaseSignoffAxis.allCases {
            reports.append(try Self.write(
                "{\"axis\":\"\(axis.rawValue)\"}",
                path: "reports/\(axis.rawValue).json",
                kind: .report,
                role: .output,
                root: root,
                producer: toolProducer
            ))
        }
        let oracleOutput = try Self.write("oracle-output", path: "reports/oracle.json", kind: .report, role: .output, root: root, producer: oracleProducer)
        let caseOutcome = ToolQualificationCaseOutcome(
            caseID: "signoff-corpus",
            coverageTags: ["all-release-axes"],
            comparisons: [ToolQualificationMetricComparison(metricID: "failure-count", observed: 0, expected: 0)]
        )
        let corpusResult = ToolCorpusQualificationResult(
            resultID: "corpus-result",
            qualificationID: "signoff-production",
            toolID: "signoff-tool",
            scope: scope,
            issuer: issuer,
            inputArtifacts: [designArtifact, pdkArtifact],
            outputArtifacts: reports,
            cases: [caseOutcome],
            checkedAt: evaluatedAt
        )
        let corpusArtifact = try Self.write(
            try corpusResult.canonicalData(),
            path: "qualification/corpus.json",
            kind: .evidence,
            role: .output,
            root: root,
            producer: issuer
        )
        let oracleResult = ToolOracleQualificationResult(
            resultID: "oracle-result",
            qualificationID: "signoff-production",
            primaryToolID: "signoff-tool",
            oracleToolID: "signoff-oracle",
            scope: scope,
            issuer: issuer,
            inputArtifacts: [designArtifact, pdkArtifact],
            primaryOutputArtifacts: reports,
            oracleOutputArtifacts: [oracleOutput],
            cases: [ToolOracleCaseComparison(
                caseID: "signoff-corpus",
                primary: caseOutcome,
                oracle: caseOutcome,
                agreementComparisons: [ToolQualificationMetricComparison(metricID: "agreement", observed: 0, expected: 0)]
            )],
            checkedAt: evaluatedAt
        )
        let oracleResultArtifact = try Self.write(
            try oracleResult.canonicalData(),
            path: "qualification/oracle.json",
            kind: .evidence,
            role: .output,
            root: root,
            producer: issuer
        )
        let healthResult = ToolHealthQualificationResult(
            resultID: "health-result",
            qualificationID: "signoff-production",
            toolID: "signoff-tool",
            scope: scope,
            issuer: issuer,
            inputArtifacts: [designArtifact, pdkArtifact],
            outputArtifacts: reports,
            checkedAt: evaluatedAt
        )
        let healthArtifact = try Self.write(
            try healthResult.canonicalData(),
            path: "qualification/health.json",
            kind: .evidence,
            role: .output,
            root: root,
            producer: issuer
        )
        let buildRequest = ToolProcessQualificationEvidenceBuildRequest(
            qualificationID: "signoff-production",
            toolID: "signoff-tool",
            scope: scope,
            identityArtifacts: ToolProcessQualificationArtifacts(
                toolExecutable: tool,
                processProfile: process,
                pdk: pdk,
                ruleDeck: deck,
                oracleExecutable: oracle
            ),
            corpusResultArtifacts: [corpusArtifact],
            oracleResultArtifacts: [oracleResultArtifact],
            healthResultArtifacts: [healthArtifact],
            inputArtifacts: [designArtifact, pdkArtifact],
            outputArtifacts: reports + [oracleOutput],
            qualifiedAt: evaluatedAt.addingTimeInterval(-10),
            expiresAt: evaluatedAt.addingTimeInterval(10)
        )
        let qualification = try await ToolProcessQualificationEvidenceBuilder().build(
            buildRequest,
            reading: LocalToolQualificationArtifactReader(workspaceRoot: root),
            at: evaluatedAt
        )
        var generatedRecords: [ReleaseSignoffEvidenceReference] = []
        for (axis, report) in zip(ReleaseSignoffAxis.allCases, reports) {
            generatedRecords.append(ReleaseSignoffEvidenceReference(
                evidenceID: "evidence-\(axis.rawValue)",
                axis: axis,
                artifact: report,
                designDigest: localDesignDigest,
                pdkDigest: localPDKDigest,
                toolID: "signoff-tool",
                toolVersion: "1.0.0",
                toolBinaryDigest: tool.sha256,
                inputArtifacts: [designArtifact, pdkArtifact],
                processQualification: qualification,
                disposition: axis == failedAxis ? .failed : .passed,
                reason: axis == failedAxis ? "failure" : nil
            ))
        }
        records = generatedRecords
        var axisResults: [SignoffAxisResult] = []
        for record in generatedRecords {
            axisResults.append(SignoffAxisResult(
                axis: record.axis,
                disposition: record.disposition == .failed ? .failed : .passed,
                evidenceIDs: [record.evidenceID],
                reason: record.disposition == .failed ? "failure" : "All required evidence records passed integrity, provenance, and qualification checks."
            ))
        }
        axisResults.sort { $0.axis < $1.axis }
        let evidenceDigest = try CanonicalSignoffEvidenceDigester().digest(generatedRecords)
        let bundle = SignoffBundle(
            bundleID: "signoff-signoff",
            profileID: "digital",
            designDigest: localDesignDigest,
            pdkDigest: localPDKDigest,
            finalLayoutDigest: String(repeating: "5", count: 64),
            axisResults: axisResults,
            waivers: [],
            evidenceDigest: evidenceDigest,
            issuedAt: issuedAt
        )
        let bundleArtifact = try Self.write(
            try bundle.canonicalData(),
            path: "release/signoff.json",
            kind: .release,
            role: .output,
            root: root
        )
        bundleReference = SignoffBundleReference(
            artifact: bundleArtifact,
            designDigest: designDigest,
            pdkDigest: pdkDigest,
            finalLayoutDigest: bundle.finalLayoutDigest
        )
    }

    func evaluate(
        waivers: [SignoffWaiver] = [],
        records suppliedRecords: [ReleaseSignoffEvidenceReference]? = nil,
        profileID: String = "digital",
        designKind: ReleaseDesignKind = .digital,
        includeProjectRoot: Bool = true
    ) async throws -> SignoffResult {
        let evaluatedRecords = suppliedRecords ?? records
        return try await DefaultSignoffEvaluator(now: { evaluatedAt }).execute(SignoffRequest(
            runID: "signoff",
            inputs: [designArtifact, pdkArtifact, bundleReference.artifact],
            profileID: profileID,
            designDigest: designDigest,
            pdkDigest: pdkDigest,
            evidence: evaluatedRecords.map(\.artifact),
            designKind: designKind,
            evidenceRecords: evaluatedRecords,
            waivers: waivers,
            projectRoot: includeProjectRoot ? root.path : nil,
            finalLayoutDigest: bundleReference.finalLayoutDigest,
            bundleArtifact: bundleReference.artifact,
            bundleIssuedAt: issuedAt
        ))
    }

    private static func write(
        _ string: String,
        path: String,
        kind: ArtifactKind,
        role: ArtifactRole,
        root: URL,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        try write(Data(string.utf8), path: path, kind: kind, role: role, root: root, producer: producer)
    }

    private static func write(
        _ data: Data,
        path: String,
        kind: ArtifactKind,
        role: ArtifactRole,
        root: URL,
        producer: ProducerIdentity? = nil
    ) throws -> ArtifactReference {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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

private func removeReleaseFixture(_ root: URL) {
    do {
        try FileManager.default.removeItem(at: root)
    } catch {
        Issue.record("Failed to remove release fixture: \(error.localizedDescription)")
    }
}
