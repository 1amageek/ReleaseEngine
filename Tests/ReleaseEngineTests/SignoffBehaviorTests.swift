import CircuiteFoundation
import Foundation
import LogicIR
import ReleaseCore
import SignoffEngine
import Testing
import ToolQualification

@Suite("Signoff behavior")
struct SignoffBehaviorTests {
    @Test("digital and mixed-signal profiles require every production axis")
    func builtInProfiles() {
        let provider = DefaultSignoffProfileProvider()
        for profileID in ["digital", "mixed-signal"] {
            let profile = provider.profile(profileID: profileID)
            #expect(profile?.requirements.count == ReleaseSignoffAxis.allCases.count)
            #expect(profile?.requirements.allSatisfy { $0.required && $0.minimumQualificationLevel == .productionEligible } == true)
        }
        let analog = provider.profile(profileID: "analog")
        #expect(analog?.requirements.count == ReleaseSignoffAxis.allCases.count)
        #expect(analog?.requirement(for: .rtlLint)?.required == false)
        #expect(analog?.requirement(for: .powerIntent)?.required == true)
    }

    @Test("production profiles include logic, RTL verification, DFT, and power intent axes")
    func productionDigitalAxes() {
        let required: Set<ReleaseSignoffAxis> = [
            .logicSynthesisEquivalence,
            .rtlLint,
            .clockDomainCrossing,
            .resetDomainCrossing,
            .formalProof,
            .scanInsertion,
            .automaticTestPatternGeneration,
            .builtInSelfTest,
            .powerIntent,
        ]
        let profile = DefaultSignoffProfileProvider.digitalProfile

        #expect(required.isSubset(of: Set(profile.requirements.filter(\.required).map(\.axis))))
    }

    @Test("missing typed evidence blocks signoff")
    func missingEvidenceBlocks() async throws {
        let request = SignoffRequest(
            runID: "missing",
            inputs: [],
            profileID: "digital",
            designDigest: String(repeating: "1", count: 64),
            pdkDigest: String(repeating: "2", count: 64),
            evidence: [],
            bundleOutput: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "release/missing.json"),
                role: .output,
                kind: .release,
                format: .json
            )
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
            evidence: [],
            bundleOutput: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: "release/lineage.json"),
                role: .output,
                kind: .release,
                format: .json
            )
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

    @Test("typed evidence inventory must exactly match declared evidence")
    func evidenceInventoryMismatchBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }

        let result = try await fixture.evaluate(evidence: Array(fixture.records.dropLast()).map(\.artifact))

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "SIGNOFF_EVIDENCE_BINDING_MISMATCH" })
    }

    @Test("all qualification artifacts must be bound as signoff inputs")
    func missingQualificationInputBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        let allInputs = fixture.boundInputs(for: fixture.records)
        let qualificationArtifact = try #require(
            fixture.records.first?.processQualification.identityArtifacts.toolExecutable
        )

        let result = try await fixture.evaluate(
            inputs: allInputs.filter { $0 != qualificationArtifact }
        )

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "SIGNOFF_INPUT_BINDING_MISSING" })
    }

    @Test("a generated signoff bundle target is immutable")
    func generatedBundleIsImmutable() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }

        let first = try await fixture.evaluate()
        let second = try await fixture.evaluate()

        #expect(first.status == .completed)
        #expect(second.status == .blocked)
        #expect(second.diagnostics.contains { $0.code.rawValue == "SIGNOFF_BUNDLE_PERSISTENCE_BLOCKED" })
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

    @Test("a valid scoped waiver is retained in the generated bundle")
    func validScopedWaiverCompletes() async throws {
        let fixture = try await SignoffFixture(failedAxis: .simulation)
        defer { removeReleaseFixture(fixture.root) }
        let waiver = SignoffWaiver(
            waiverID: "simulation-waiver",
            axis: .simulation,
            reason: "approved scoped exception",
            authority: "review-board",
            approvedAt: Date(timeIntervalSince1970: 500),
            expiresAt: Date(timeIntervalSince1970: 2_000),
            affectedEvidenceIDs: ["evidence-simulation"],
            designDigest: fixture.designDigest,
            pdkDigest: fixture.pdkDigest
        )

        let result = try await fixture.evaluate(waivers: [waiver])

        #expect(result.status == .completed)
        #expect(result.payload.bundle != nil)
        #expect(result.payload.axisResults.contains {
            $0.axis == .simulation
                && $0.disposition == .waived
                && $0.waiverID == waiver.waiverID
        })
    }

    @Test("duplicate waiver axes fail closed")
    func duplicateWaiverAxisBlocks() async throws {
        let fixture = try await SignoffFixture(failedAxis: .simulation)
        defer { removeReleaseFixture(fixture.root) }
        let approvedAt = Date(timeIntervalSince1970: 500)
        let waivers = ["first", "second"].map {
            SignoffWaiver(
                waiverID: $0,
                axis: .simulation,
                reason: "scoped exception",
                authority: "review-board",
                approvedAt: approvedAt,
                expiresAt: Date(timeIntervalSince1970: 2_000),
                affectedEvidenceIDs: ["evidence-simulation"],
                designDigest: fixture.designDigest,
                pdkDigest: fixture.pdkDigest
            )
        }

        let result = try await fixture.evaluate(waivers: waivers)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "DUPLICATE_WAIVER_AXIS" })
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

    @Test("operational provenance must bind the qualified implementation")
    func operationalProvenanceIdentityMismatchBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        let original = records[0].executionProvenance
        records[0].executionProvenance = try ExecutionProvenance(
            producer: ProducerIdentity(
                kind: .engine,
                identifier: "unqualified-engine",
                version: "1.0.0"
            ),
            inputs: original.inputs,
            startedAt: original.startedAt,
            completedAt: original.completedAt
        )

        let result = try await fixture.evaluate(records: records)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "OPERATIONAL_EXECUTION_IDENTITY_MISMATCH"
        })
    }

    @Test("operational provenance cannot claim future completion")
    func futureOperationalCompletionBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        let original = records[0].executionProvenance
        records[0].executionProvenance = try ExecutionProvenance(
            producer: original.producer,
            supportingTools: original.supportingTools,
            inputs: original.inputs,
            startedAt: fixture.evaluatedAt,
            completedAt: fixture.evaluatedAt.addingTimeInterval(1)
        )

        let result = try await fixture.evaluate(records: records)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "OPERATIONAL_EXECUTION_TIMESTAMP_INVALID"
        })
    }

    @Test("operational provenance cannot omit a declared input")
    func missingOperationalProvenanceInputBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        let original = records[0].executionProvenance
        records[0].executionProvenance = try ExecutionProvenance(
            producer: original.producer,
            supportingTools: original.supportingTools,
            inputs: Array(original.inputs.dropLast()),
            invocation: original.invocation,
            startedAt: original.startedAt,
            completedAt: original.completedAt
        )

        let result = try await fixture.evaluate(records: records)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "OPERATIONAL_EXECUTION_INPUT_MISMATCH"
        })
    }

    @Test("operational provenance cannot add an undeclared input")
    func extraOperationalProvenanceInputBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        let original = records[0].executionProvenance
        let undeclared = records[0].processQualification.identityArtifacts.toolExecutable
        records[0].executionProvenance = try ExecutionProvenance(
            producer: original.producer,
            supportingTools: original.supportingTools,
            inputs: original.inputs + [undeclared],
            invocation: original.invocation,
            startedAt: original.startedAt,
            completedAt: original.completedAt
        )

        let result = try await fixture.evaluate(records: records)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "OPERATIONAL_EXECUTION_INPUT_MISMATCH"
        })
    }

    @Test("operational artifact producer cannot be substituted")
    func operationalArtifactProducerSubstitutionBlocks() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        let artifact = records[0].artifact
        records[0].artifact = ArtifactReference(
            id: artifact.id,
            locator: artifact.locator,
            digest: artifact.digest,
            byteCount: artifact.byteCount,
            producer: try ProducerIdentity(
                kind: .tool,
                identifier: "substituted-signoff-tool",
                version: "1.0.0"
            )
        )

        let result = try await fixture.evaluate(records: records)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains {
            $0.code.rawValue == "OPERATIONAL_ARTIFACT_PROVENANCE_MISMATCH"
        })
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

    @Test("an explicitly blocked producer result blocks its release axis")
    func blockedEvidenceCannotPassSignoff() async throws {
        let fixture = try await SignoffFixture()
        defer { removeReleaseFixture(fixture.root) }
        var records = fixture.records
        records[0].disposition = .blocked
        records[0].reason = "required analysis did not complete"

        let result = try await fixture.evaluate(records: records)

        #expect(result.status == .blocked)
        #expect(result.diagnostics.contains { $0.code.rawValue == "EVIDENCE_REPORTED_BLOCKED" })
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
        let localDesignDigest = designArtifact.digest.hexadecimalValue
        let localPDKDigest = pdkArtifact.digest.hexadecimalValue
        designDigest = localDesignDigest
        pdkDigest = localPDKDigest

        let toolProducer = try ProducerIdentity(kind: .tool, identifier: "signoff-tool", version: "1.0.0")
        let oracleProducer = try ProducerIdentity(kind: .tool, identifier: "signoff-oracle", version: "2.0.0")
        let issuer = try ProducerIdentity(kind: .engine, identifier: "qualification-engine", version: "1.0.0")
        let tool = try Self.write("tool", path: "identity/tool", kind: .other, role: .input, root: root, producer: toolProducer)
        let operationalToolProducer = try ProducerIdentity(
            kind: .tool,
            identifier: "signoff-tool",
            version: "1.0.0",
            build: tool.digest.hexadecimalValue
        )
        let process = try Self.write("process", path: "identity/process.json", kind: .technology, role: .input, root: root)
        let pdk = pdkArtifact
        let deck = try Self.write("deck", path: "identity/deck.json", kind: .ruleDeck, role: .input, root: root)
        let oracle = try Self.write("oracle", path: "identity/oracle", kind: .other, role: .input, root: root, producer: oracleProducer)
        let scope = ToolQualificationScope(
            implementationID: "signoff-tool",
            toolVersion: "1.0.0",
            binaryDigest: tool.digest.hexadecimalValue,
            algorithmVersion: "signoff-v1",
            processProfileID: "process",
            processProfileDigest: process.digest.hexadecimalValue,
            deckDigest: deck.digest.hexadecimalValue,
            pdkID: "pdk",
            pdkDigest: pdk.digest.hexadecimalValue,
            oracle: ToolOracleQualificationScope(
                implementationID: "signoff-oracle",
                version: "2.0.0",
                binaryDigest: oracle.digest.hexadecimalValue
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
                producer: operationalToolProducer
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
                agreementComparisons: [ToolOracleMetricComparison(
                    metricID: "failure-count",
                    primaryObserved: 0,
                    oracleObserved: 0
                )]
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
                toolBinaryDigest: tool.digest.hexadecimalValue,
                inputArtifacts: [designArtifact, pdkArtifact],
                executionProvenance: try ExecutionProvenance(
                    producer: operationalToolProducer,
                    inputs: [designArtifact, pdkArtifact],
                    startedAt: evaluatedAt.addingTimeInterval(-2),
                    completedAt: evaluatedAt.addingTimeInterval(-1)
                ),
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
            evidenceRecords: generatedRecords,
            evidenceArtifacts: generatedRecords.map(\.artifact),
            toolQualificationScopes: [qualification.scope],
            evidenceDigest: evidenceDigest,
            issuedAt: evaluatedAt
        )
        let bundleBytes = try bundle.canonicalData()
        let bundleLocator = ArtifactLocator(
            location: try ArtifactLocation(workspaceRelativePath: "release/signoff.json"),
            role: .output,
            kind: .release,
            format: .json
        )
        let bundleArtifact = ArtifactReference(
            locator: bundleLocator,
            digest: try SHA256ContentDigester().digest(data: bundleBytes),
            byteCount: UInt64(bundleBytes.count),
            producer: try ProducerIdentity(
                kind: .engine,
                identifier: "native.release.signoff",
                version: "2.0.0",
                build: ReleaseRuntimeIdentity.currentExecutableDigest()
            )
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
        evidence suppliedEvidence: [ArtifactReference]? = nil,
        inputs suppliedInputs: [ArtifactReference]? = nil,
        profileID: String = "digital",
        designKind: ReleaseDesignKind = .digital,
        includeProjectRoot: Bool = true
    ) async throws -> SignoffResult {
        let evaluatedRecords = suppliedRecords ?? records
        return try await DefaultSignoffEvaluator(now: { evaluatedAt }).execute(SignoffRequest(
            runID: "signoff",
            inputs: suppliedInputs ?? boundInputs(for: evaluatedRecords),
            profileID: profileID,
            designDigest: designDigest,
            pdkDigest: pdkDigest,
            evidence: suppliedEvidence ?? evaluatedRecords.map(\.artifact),
            designKind: designKind,
            evidenceRecords: evaluatedRecords,
            waivers: waivers,
            projectRoot: includeProjectRoot ? root.path : nil,
            finalLayoutDigest: bundleReference.finalLayoutDigest,
            bundleOutput: bundleReference.artifact.locator
        ))
    }

    func boundInputs(
        for records: [ReleaseSignoffEvidenceReference]
    ) -> [ArtifactReference] {
        Array(Set(
            [designArtifact, pdkArtifact]
                + records.flatMap(\.inputArtifacts)
                + records.flatMap { record in
                    let qualification = record.processQualification
                    return qualification.identityArtifacts.all
                        + qualification.evidenceArtifacts
                        + qualification.inputArtifacts
                        + qualification.outputArtifacts
                }
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
