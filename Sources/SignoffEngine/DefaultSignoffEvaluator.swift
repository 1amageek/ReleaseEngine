import Foundation
import LogicIR
import ReleaseCore
import ToolQualification
import CircuiteFoundation

public struct DefaultSignoffEvaluator: SignoffEvaluating {
    private let profileProvider: any SignoffProfileProviding
    private let evidenceValidator: any SignoffEvidenceValidating
    private let evidenceDigester: any SignoffEvidenceDigesting
    private let artifactPersister: any ReleaseArtifactPersisting
    private let now: @Sendable () -> Date

    public init(
        profileProvider: any SignoffProfileProviding = DefaultSignoffProfileProvider(),
        evidenceValidator: any SignoffEvidenceValidating = DefaultSignoffEvidenceValidator(),
        evidenceDigester: any SignoffEvidenceDigesting = CanonicalSignoffEvidenceDigester(),
        artifactPersister: any ReleaseArtifactPersisting = LocalReleaseArtifactStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.profileProvider = profileProvider
        self.evidenceValidator = evidenceValidator
        self.evidenceDigester = evidenceDigester
        self.artifactPersister = artifactPersister
        self.now = now
    }

    public func execute(
        _ request: SignoffRequest
    ) async throws -> SignoffResult {
        let startedAt = now()
        let profile = profileProvider.profile(profileID: request.profileID)

        guard request.schemaVersion == SignoffRequest.currentSchemaVersion else {
            return try blockedEnvelope(
                request: request,
                startedAt: startedAt,
                diagnostics: [diagnostic("INVALID_REQUEST_SCHEMA", "Unsupported signoff request schema version.", entity: request.runID)]
            )
        }
        guard !request.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return try blockedEnvelope(
                request: request,
                startedAt: startedAt,
                diagnostics: [diagnostic("RUN_ID_REQUIRED", "Signoff run ID must not be empty.", entity: nil)]
            )
        }
        guard let profile else {
            return try blockedEnvelope(
                request: request,
                startedAt: startedAt,
                diagnostics: [diagnostic("SIGNOFF_PROFILE_NOT_FOUND", "The requested signoff profile is not registered.", entity: request.profileID)]
            )
        }
        guard profile.isValid else {
            return try blockedEnvelope(
                request: request,
                startedAt: startedAt,
                diagnostics: [diagnostic("INVALID_SIGNOFF_PROFILE", "The selected signoff profile is not schema-valid or contains duplicate/empty axis requirements.", entity: request.profileID)]
            )
        }

        var diagnostics: [DesignDiagnostic] = []
        diagnostics.append(contentsOf: validateRequestArtifactBindings(request))
        if profile.designKind != request.designKind {
            diagnostics.append(diagnostic(
                "SIGNOFF_PROFILE_DESIGN_KIND_MISMATCH",
                "The request design kind does not match the selected signoff profile.",
                entity: request.profileID
            ))
        }

        let provenanceIssues = LogicDesignProvenanceValidation.issues(
            for: request.designDigest,
            provenance: request.designProvenance
        )
        diagnostics.append(contentsOf: provenanceIssues
            .filter { $0.code != "design_digest_missing" }
            .map { issue in
                diagnostic(
                    issue.diagnosticCode,
                    issue.message,
                    entity: request.runID
                )
            })

        let evidenceValidation = evidenceValidator.validate(
            evidence: request.evidenceRecords,
            projectRoot: request.projectRoot.map(URL.init(fileURLWithPath:)),
            designDigest: request.designDigest,
            pdkDigest: request.pdkDigest,
            profile: profile,
            evaluatedAt: startedAt
        )
        diagnostics.append(contentsOf: evidenceValidation.diagnostics)

        var axisResults: [SignoffAxisResult] = []
        var invalidWaiverAxes = Set<ReleaseSignoffAxis>()
        var validWaivers: [ReleaseSignoffAxis: SignoffWaiver] = [:]
        var seenWaiverIDs = Set<String>()
        var seenWaiverAxes = Set<ReleaseSignoffAxis>()

        for waiver in request.waivers {
            if !seenWaiverIDs.insert(waiver.waiverID).inserted {
                diagnostics.append(diagnostic(
                    "DUPLICATE_WAIVER_ID",
                    "Waiver IDs must be unique within a signoff request.",
                    entity: waiver.waiverID
                ))
                invalidWaiverAxes.insert(waiver.axis)
                continue
            }
            if !seenWaiverAxes.insert(waiver.axis).inserted {
                diagnostics.append(diagnostic(
                    "DUPLICATE_WAIVER_AXIS",
                    "A signoff axis can have at most one scoped waiver in a release request.",
                    entity: waiver.axis.rawValue
                ))
                invalidWaiverAxes.insert(waiver.axis)
                continue
            }
            let result = validateWaiver(
                waiver,
                request: request,
                records: request.evidenceRecords,
                evaluatedAt: startedAt
            )
            diagnostics.append(contentsOf: result.diagnostics)
            if result.isValid {
                validWaivers[waiver.axis] = waiver
            } else {
                invalidWaiverAxes.insert(waiver.axis)
            }
        }

        for requirement in profile.requirements.sorted(by: { $0.axis < $1.axis }) {
            let axis = requirement.axis
            let records = request.evidenceRecords.filter { $0.axis == axis }
            let evidenceIDs = records.map(\.evidenceID).sorted()
            let codes = evidenceValidation.diagnosticCodesByAxis[axis, default: []]

            if !requirement.required {
                axisResults.append(SignoffAxisResult(
                    axis: axis,
                    disposition: .profileApprovedNotApplicable,
                    evidenceIDs: evidenceIDs,
                    reason: "The selected profile explicitly marks this axis as not applicable."
                ))
                continue
            }

            if profile.designKind != request.designKind {
                axisResults.append(SignoffAxisResult(
                    axis: axis,
                    disposition: .blocked,
                    evidenceIDs: evidenceIDs,
                    diagnosticCodes: codes + ["SIGNOFF_PROFILE_DESIGN_KIND_MISMATCH"],
                    reason: "The profile cannot be applied to this design kind."
                ))
                continue
            }
            if records.count < requirement.minimumEvidenceCount {
                axisResults.append(SignoffAxisResult(
                    axis: axis,
                    disposition: .blocked,
                    evidenceIDs: evidenceIDs,
                    diagnosticCodes: codes + ["REQUIRED_EVIDENCE_MISSING"],
                    reason: "The required number of evidence records was not supplied."
                ))
                diagnostics.append(diagnostic(
                    "REQUIRED_EVIDENCE_MISSING",
                    "A required signoff axis has insufficient evidence records.",
                    entity: axis.rawValue
                ))
                continue
            }
            if evidenceValidation.blockedAxes.contains(axis) || invalidWaiverAxes.contains(axis) {
                axisResults.append(SignoffAxisResult(
                    axis: axis,
                    disposition: .blocked,
                    evidenceIDs: evidenceIDs,
                    diagnosticCodes: codes,
                    reason: invalidWaiverAxes.contains(axis)
                        ? "The axis contains an invalid waiver and remains blocked."
                        : "Evidence prerequisites for this axis are not satisfied."
                ))
                continue
            }

            let failedRecords = records.filter { $0.disposition == .failed }
            if !failedRecords.isEmpty {
                if let waiver = validWaivers[axis],
                   Set(failedRecords.map(\.evidenceID)).isSubset(of: Set(waiver.affectedEvidenceIDs)) {
                    axisResults.append(SignoffAxisResult(
                        axis: axis,
                        disposition: .waived,
                        evidenceIDs: evidenceIDs,
                        diagnosticCodes: codes,
                        reason: "The recorded finding is covered by a valid, scoped waiver.",
                        waiverID: waiver.waiverID
                    ))
                } else {
                    axisResults.append(SignoffAxisResult(
                        axis: axis,
                        disposition: .failed,
                        evidenceIDs: evidenceIDs,
                        diagnosticCodes: codes,
                        reason: failedRecords.compactMap(\.reason).joined(separator: " ").ifEmpty("A signoff evidence record reported failure.")
                    ))
                }
            } else {
                axisResults.append(SignoffAxisResult(
                    axis: axis,
                    disposition: .passed,
                    evidenceIDs: evidenceIDs,
                    diagnosticCodes: codes,
                    reason: "All required evidence records passed integrity, provenance, and qualification checks."
                ))
            }
        }

        if !isSHA256(request.designDigest) || !isSHA256(request.pdkDigest) {
            diagnostics.append(diagnostic(
                "INVALID_REQUEST_PROVENANCE_DIGEST",
                "Design and PDK digests must be SHA-256 values.",
                entity: request.runID
            ))
        }

        let blockedAxes = axisResults
            .filter { $0.disposition == .blocked }
            .map(\.axis.rawValue)
            .sorted() + (provenanceIssues.isEmpty ? [] : ["provenance"])
        var status: ReleaseExecutionStatus = .completed
        if !blockedAxes.isEmpty || !diagnostics.filter({ $0.severity == .error }).isEmpty {
            status = .blocked
        } else if axisResults.contains(where: { $0.disposition == .failed }) {
            status = .failed
        }

        let eligible = status == .completed
            && axisResults.allSatisfy { $0.disposition.isReleaseEligible }
        var bundleReference: SignoffBundleReference?
        if eligible {
            guard let finalLayoutDigest = request.finalLayoutDigest, isSHA256(finalLayoutDigest) else {
                diagnostics.append(diagnostic(
                    "FINAL_LAYOUT_DIGEST_REQUIRED",
                    "A passing signoff bundle must bind to a final layout SHA-256 digest.",
                    entity: request.runID
                ))
                status = .blocked
                bundleReference = nil
                return try envelope(
                    request: request,
                    status: status,
                    diagnostics: diagnostics,
                    artifacts: request.evidenceRecords.map(\.artifact),
                    startedAt: startedAt,
                    payload: SignoffPayload(
                        passed: false,
                        blockedAxes: blockedAxes + ["bundle"],
                        bundle: nil,
                        profileID: profile.profileID,
                        designDigest: request.designDigest,
                        pdkDigest: request.pdkDigest,
                        axisResults: axisResults,
                        waivers: request.waivers
                    )
                )
            }
            guard request.bundleOutput.location.storage == .workspaceRelative,
                  request.bundleOutput.role == .output,
                  request.bundleOutput.kind == .release,
                  request.bundleOutput.format == .json else {
                diagnostics.append(diagnostic(
                    "SIGNOFF_BUNDLE_TARGET_INVALID",
                    "A passing signoff result must target a project-relative release output in JSON format.",
                    entity: request.runID
                ))
                status = .blocked
                bundleReference = nil
                return try envelope(
                    request: request,
                    status: status,
                    diagnostics: diagnostics,
                    artifacts: request.evidenceRecords.map(\.artifact),
                    startedAt: startedAt,
                    payload: SignoffPayload(
                        passed: false,
                        blockedAxes: blockedAxes + ["bundle"],
                        bundle: nil,
                        profileID: profile.profileID,
                        designDigest: request.designDigest,
                        pdkDigest: request.pdkDigest,
                        axisResults: axisResults,
                        waivers: request.waivers
                    )
                )
            }

            guard let projectRoot = request.projectRoot.map(URL.init(fileURLWithPath:)) else {
                diagnostics.append(diagnostic(
                    "SIGNOFF_BUNDLE_PROJECT_ROOT_REQUIRED",
                    "A project root is required to generate and verify the immutable signoff bundle.",
                    entity: request.runID
                ))
                return try envelope(
                    request: request,
                    status: .blocked,
                    diagnostics: diagnostics,
                    artifacts: request.evidenceRecords.map(\.artifact),
                    startedAt: startedAt,
                    payload: SignoffPayload(
                        passed: false,
                        blockedAxes: blockedAxes + ["bundle"],
                        bundle: nil,
                        profileID: profile.profileID,
                        designDigest: request.designDigest,
                        pdkDigest: request.pdkDigest,
                        axisResults: axisResults,
                        waivers: request.waivers
                    )
                )
            }
            let evidenceDigest = try evidenceDigester.digest(request.evidenceRecords)
            let toolQualificationScopes = Array(Set(
                request.evidenceRecords.map(\.processQualification.scope)
            ))
            let bundle = SignoffBundle(
                bundleID: "\(request.runID)-signoff",
                profileID: profile.profileID,
                designDigest: request.designDigest,
                designProvenance: request.designProvenance,
                pdkDigest: request.pdkDigest,
                finalLayoutDigest: finalLayoutDigest,
                axisResults: axisResults,
                waivers: request.waivers,
                evidenceRecords: request.evidenceRecords,
                evidenceArtifacts: request.evidenceRecords.map(\.artifact),
                toolQualificationScopes: toolQualificationScopes,
                evidenceDigest: evidenceDigest,
                issuedAt: now()
            )
            do {
                let bytes = try bundle.canonicalData()
                let producer = try ProducerIdentity(
                    kind: .engine,
                    identifier: "native.release.signoff",
                    version: "2.0.0",
                    build: ReleaseRuntimeIdentity.currentExecutableDigest()
                )
                let bundleArtifact = try await artifactPersister.persist(
                    ReleaseArtifactPersistenceRequest(
                        locator: request.bundleOutput,
                        bytes: bytes,
                        producer: producer
                    ),
                    relativeTo: projectRoot
                )
                try await verifyPersistedBundle(
                    expected: bundle,
                    artifact: bundleArtifact,
                    expectedLocator: request.bundleOutput,
                    expectedBytes: bytes,
                    producer: producer,
                    projectRoot: projectRoot
                )
                bundleReference = SignoffBundleReference(
                    artifact: bundleArtifact,
                    designDigest: request.designDigest,
                    designProvenance: request.designProvenance,
                    pdkDigest: request.pdkDigest,
                    finalLayoutDigest: finalLayoutDigest
                )
            } catch {
                diagnostics.append(diagnostic(
                    "SIGNOFF_BUNDLE_PERSISTENCE_BLOCKED",
                    "The generated signoff bundle could not be persisted and verified immutably: \(error.localizedDescription)",
                    entity: request.bundleOutput.location.value
                ))
                return try envelope(
                    request: request,
                    status: .blocked,
                    diagnostics: diagnostics,
                    artifacts: request.evidenceRecords.map(\.artifact),
                    startedAt: startedAt,
                    payload: SignoffPayload(
                        passed: false,
                        blockedAxes: blockedAxes + ["bundle"],
                        bundle: nil,
                        profileID: profile.profileID,
                        designDigest: request.designDigest,
                        pdkDigest: request.pdkDigest,
                        axisResults: axisResults,
                        waivers: request.waivers
                    )
                )
            }
        }

        let artifacts = uniqueArtifacts(request.evidenceRecords.map(\.artifact) + [bundleReference?.artifact].compactMap { $0 })
        let payload = SignoffPayload(
            passed: bundleReference != nil && status == .completed,
            blockedAxes: blockedAxes,
            bundle: bundleReference,
            profileID: profile.profileID,
            designDigest: request.designDigest,
            pdkDigest: request.pdkDigest,
            axisResults: axisResults,
            waivers: request.waivers
        )
        return try envelope(
            request: request,
            status: status,
            diagnostics: diagnostics,
            artifacts: artifacts,
            startedAt: startedAt,
            payload: payload
        )
    }

    private func validateWaiver(
        _ waiver: SignoffWaiver,
        request: SignoffRequest,
        records: [ReleaseSignoffEvidenceReference],
        evaluatedAt: Date
    ) -> (isValid: Bool, diagnostics: [DesignDiagnostic]) {
        var diagnostics: [DesignDiagnostic] = []
        func fail(_ code: String, _ message: String) {
            diagnostics.append(diagnostic(code, message, entity: waiver.waiverID))
        }
        let affected = records.filter { waiver.affectedEvidenceIDs.contains($0.evidenceID) }
        if waiver.waiverID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail("WAIVER_ID_REQUIRED", "Waiver ID must not be empty.") }
        if waiver.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail("WAIVER_REASON_REQUIRED", "Waiver reason must not be empty.") }
        if waiver.authority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail("WAIVER_AUTHORITY_REQUIRED", "Waiver authority must not be empty.") }
        if waiver.affectedEvidenceIDs.isEmpty { fail("WAIVER_SCOPE_REQUIRED", "A waiver must identify affected evidence IDs.") }
        if waiver.expiresAt <= waiver.approvedAt || waiver.expiresAt <= evaluatedAt { fail("WAIVER_EXPIRED_OR_INVALID", "Waiver expiry must be after approval and in the future.") }
        if waiver.designDigest != request.designDigest { fail("WAIVER_DESIGN_DIGEST_MISMATCH", "Waiver is bound to a different design revision.") }
        if waiver.pdkDigest != request.pdkDigest { fail("WAIVER_PDK_DIGEST_MISMATCH", "Waiver is bound to a different PDK revision.") }
        if affected.count != waiver.affectedEvidenceIDs.count { fail("WAIVER_EVIDENCE_NOT_FOUND", "Waiver scope contains an evidence ID that is not present in the request.") }
        if affected.contains(where: { $0.axis != waiver.axis }) { fail("WAIVER_AXIS_MISMATCH", "Waiver scope contains evidence from another signoff axis.") }
        if (waiver.toolID == nil) != (waiver.toolDigest == nil) { fail("WAIVER_TOOL_SCOPE_INCOMPLETE", "Waiver tool scope must provide both tool ID and tool digest, or neither.") }
        if let toolID = waiver.toolID, affected.contains(where: { $0.toolID != toolID }) { fail("WAIVER_TOOL_SCOPE_MISMATCH", "Waiver tool scope does not match affected evidence.") }
        if let toolDigest = waiver.toolDigest, affected.contains(where: { $0.toolBinaryDigest != toolDigest }) { fail("WAIVER_TOOL_DIGEST_MISMATCH", "Waiver tool digest scope does not match affected evidence.") }
        return (diagnostics.isEmpty, diagnostics)
    }

    private func uniqueArtifacts(_ artifacts: [ArtifactReference]) -> [ArtifactReference] {
        Array(Set(artifacts)).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func validateRequestArtifactBindings(
        _ request: SignoffRequest
    ) -> [DesignDiagnostic] {
        var diagnostics: [DesignDiagnostic] = []
        let declaredEvidence = Set(request.evidence)
        let typedEvidence = Set(request.evidenceRecords.map(\.artifact))
        if declaredEvidence != typedEvidence {
            diagnostics.append(diagnostic(
                "SIGNOFF_EVIDENCE_BINDING_MISMATCH",
                "The evidence artifact inventory must exactly match the typed signoff evidence records.",
                entity: request.runID
            ))
        }

        let declaredInputs = Set(request.inputs)
        var requiredInputs = Set(request.evidenceRecords.flatMap(\.inputArtifacts))
        for qualification in request.evidenceRecords.map(\.processQualification) {
            requiredInputs.formUnion(qualification.identityArtifacts.all)
            requiredInputs.formUnion(qualification.evidenceArtifacts)
            requiredInputs.formUnion(qualification.inputArtifacts)
            requiredInputs.formUnion(qualification.outputArtifacts)
        }
        for missing in requiredInputs.subtracting(declaredInputs).sorted(by: { $0.path < $1.path }) {
            diagnostics.append(diagnostic(
                "SIGNOFF_INPUT_BINDING_MISSING",
                "The signoff request must bind every design, PDK, qualification, and bundle input used by the decision.",
                entity: missing.path
            ))
        }
        return diagnostics
    }

    private func verifyPersistedBundle(
        expected: SignoffBundle,
        artifact: ArtifactReference,
        expectedLocator: ArtifactLocator,
        expectedBytes: Data,
        producer: ProducerIdentity,
        projectRoot: URL
    ) async throws {
        guard artifact.locator == expectedLocator,
              artifact.producer == producer else {
            throw SignoffBundlePersistenceError.referenceMismatch
        }
        let expectedDigest = try SHA256ContentDigester().digest(data: expectedBytes)
        guard artifact.digest == expectedDigest,
              artifact.byteCount == UInt64(expectedBytes.count) else {
            throw SignoffBundlePersistenceError.referenceMismatch
        }
        let persistedBytes = try await artifactPersister.load(artifact, relativeTo: projectRoot)
        guard persistedBytes == expectedBytes,
              try SignoffBundle.decodeCanonical(from: persistedBytes) == expected else {
            throw SignoffBundlePersistenceError.contentMismatch
        }
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
        }
    }

    private func diagnostic(_ code: String, _ message: String, entity: String?) -> DesignDiagnostic {
        DesignDiagnostic(
            severity: .error,
            code: code,
            message: message,
            entity: entity,
            suggestedActions: ["inspect_release_contract", "retain_or_rebuild_required_evidence"]
        )
    }

    private func envelope(
        request: SignoffRequest,
        status: ReleaseExecutionStatus,
        diagnostics: [DesignDiagnostic],
        artifacts: [ArtifactReference],
        startedAt: Date,
        payload: SignoffPayload
    ) throws -> SignoffResult {
        let metadata = try ExecutionProvenance(
            producer: ProducerIdentity(
                kind: .engine,
                identifier: "native.release.signoff",
                version: "2.0.0",
                build: ReleaseRuntimeIdentity.currentExecutableDigest()
            ),
            inputs: uniqueArtifacts(request.inputs + request.evidence),
            invocation: ExecutionInvocation.inProcess(
                entryPoint: "SignoffEngine.DefaultSignoffEvaluator.execute"
            ),
            environment: try ReleaseRuntimeIdentity.environmentFingerprint(
                toolchain: "native.release.signoff-2.0.0"
            ),
            startedAt: startedAt,
            completedAt: now()
        )
        return SignoffResult(
            schemaVersion: SignoffRequest.currentSchemaVersion,
            runID: request.runID,
            status: status,
            diagnostics: diagnostics,
            artifacts: artifacts,
            metadata: metadata,
            payload: payload
        )
    }

    private func blockedEnvelope(
        request: SignoffRequest,
        startedAt: Date,
        diagnostics: [DesignDiagnostic]
    ) throws -> SignoffResult {
        try envelope(
            request: request,
            status: .blocked,
            diagnostics: diagnostics,
            artifacts: [],
            startedAt: startedAt,
            payload: SignoffPayload(
                passed: false,
                blockedAxes: ["request"],
                bundle: nil,
                profileID: request.profileID,
                designDigest: request.designDigest,
                pdkDigest: request.pdkDigest
            )
        )
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
