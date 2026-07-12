import Foundation
import ReleaseCore
import ToolQualification
import XcircuitePackage

public struct DefaultSignoffEvaluator: SignoffEvaluating {
    private let profileProvider: any SignoffProfileProviding
    private let evidenceValidator: any SignoffEvidenceValidating
    private let now: @Sendable () -> Date

    public init(
        profileProvider: any SignoffProfileProviding = DefaultSignoffProfileProvider(),
        evidenceValidator: any SignoffEvidenceValidating = DefaultSignoffEvidenceValidator(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.profileProvider = profileProvider
        self.evidenceValidator = evidenceValidator
        self.now = now
    }

    public func execute(
        _ request: SignoffRequest
    ) async throws -> XcircuiteEngineResultEnvelope<SignoffPayload> {
        let startedAt = now()
        let profile = profileProvider.profile(profileID: request.profileID)
        let metadata = XcircuiteEngineExecutionMetadata(
            engineID: "release.signoff",
            implementationID: "native.release.signoff",
            implementationVersion: "1.0.0",
            startedAt: startedAt,
            completedAt: now()
        )

        guard request.schemaVersion == SignoffRequest.currentSchemaVersion else {
            return blockedEnvelope(
                request: request,
                metadata: metadata,
                diagnostics: [diagnostic("INVALID_REQUEST_SCHEMA", "Unsupported signoff request schema version.", entity: request.runID)]
            )
        }
        guard !request.runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return blockedEnvelope(
                request: request,
                metadata: metadata,
                diagnostics: [diagnostic("RUN_ID_REQUIRED", "Signoff run ID must not be empty.", entity: nil)]
            )
        }
        guard let profile else {
            return blockedEnvelope(
                request: request,
                metadata: metadata,
                diagnostics: [diagnostic("SIGNOFF_PROFILE_NOT_FOUND", "The requested signoff profile is not registered.", entity: request.profileID)]
            )
        }
        guard profile.isValid else {
            return blockedEnvelope(
                request: request,
                metadata: metadata,
                diagnostics: [diagnostic("INVALID_SIGNOFF_PROFILE", "The selected signoff profile is not schema-valid or contains duplicate/empty axis requirements.", entity: request.profileID)]
            )
        }

        var diagnostics: [XcircuiteEngineDiagnostic] = []
        if profile.designKind != request.designKind {
            diagnostics.append(diagnostic(
                "SIGNOFF_PROFILE_DESIGN_KIND_MISMATCH",
                "The request design kind does not match the selected signoff profile.",
                entity: request.profileID
            ))
        }

        let evidenceValidation = evidenceValidator.validate(
            evidence: request.evidenceRecords,
            projectRoot: request.projectRoot.map(URL.init(fileURLWithPath:)),
            designDigest: request.designDigest,
            pdkDigest: request.pdkDigest,
            profile: profile
        )
        diagnostics.append(contentsOf: evidenceValidation.diagnostics)

        var axisResults: [SignoffAxisResult] = []
        var invalidWaiverAxes = Set<ReleaseSignoffAxis>()
        var validWaivers: [ReleaseSignoffAxis: SignoffWaiver] = [:]

        for waiver in request.waivers {
            let result = validateWaiver(waiver, request: request, records: request.evidenceRecords)
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
            .sorted()
        var status: XcircuiteEngineExecutionStatus = .completed
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
                    "An approved signoff bundle must bind to a final layout SHA-256 digest.",
                    entity: request.runID
                ))
                status = .blocked
                bundleReference = nil
                return envelope(
                    request: request,
                    status: status,
                    diagnostics: diagnostics,
                    artifacts: request.evidenceRecords.map(\.artifact),
                    metadata: metadata,
                    payload: SignoffPayload(
                        approved: false,
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
            guard let bundleArtifact = request.bundleArtifact,
                  bundleArtifact.kind == .release,
                  !bundleArtifact.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  isSHA256(bundleArtifact.sha256 ?? ""),
                  let byteCount = bundleArtifact.byteCount,
                  byteCount >= 0 else {
                diagnostics.append(diagnostic(
                    "SIGNOFF_BUNDLE_ARTIFACT_REQUIRED",
                    "An approved signoff result must provide an immutable release artifact reference with digest and byte count.",
                    entity: request.runID
                ))
                status = .blocked
                bundleReference = nil
                return envelope(
                    request: request,
                    status: status,
                    diagnostics: diagnostics,
                    artifacts: request.evidenceRecords.map(\.artifact),
                    metadata: metadata,
                    payload: SignoffPayload(
                        approved: false,
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

            let issuedAt = now()
            let evidenceDigest = makeEvidenceDigest(request.evidenceRecords)
            let unsignedBundle = SignoffBundle(
                bundleID: "(request.runID)-signoff",
                profileID: profile.profileID,
                designDigest: request.designDigest,
                pdkDigest: request.pdkDigest,
                finalLayoutDigest: finalLayoutDigest,
                axisResults: axisResults,
                waivers: request.waivers,
                evidenceDigest: evidenceDigest,
                issuedAt: issuedAt,
                approvalDigest: ""
            )
            let bundle = SignoffBundle(
                bundleID: unsignedBundle.bundleID,
                profileID: unsignedBundle.profileID,
                designDigest: unsignedBundle.designDigest,
                pdkDigest: unsignedBundle.pdkDigest,
                finalLayoutDigest: unsignedBundle.finalLayoutDigest,
                axisResults: unsignedBundle.axisResults,
                waivers: unsignedBundle.waivers,
                evidenceDigest: unsignedBundle.evidenceDigest,
                issuedAt: unsignedBundle.issuedAt,
                approvalDigest: unsignedBundle.computedApprovalDigest()
            )
            bundleReference = SignoffBundleReference(
                artifact: bundleArtifact,
                designDigest: request.designDigest,
                pdkDigest: request.pdkDigest,
                finalLayoutDigest: finalLayoutDigest,
                bundleDigest: bundle.approvalDigest,
                approved: true
            )
        }

        let artifacts = uniqueArtifacts(request.evidenceRecords.map(\.artifact) + [bundleReference?.artifact].compactMap { $0 })
        let payload = SignoffPayload(
            approved: bundleReference != nil && status == .completed,
            blockedAxes: blockedAxes,
            bundle: bundleReference,
            profileID: profile.profileID,
            designDigest: request.designDigest,
            pdkDigest: request.pdkDigest,
            axisResults: axisResults,
            waivers: request.waivers
        )
        return envelope(
            request: request,
            status: status,
            diagnostics: diagnostics,
            artifacts: artifacts,
            metadata: metadata,
            payload: payload
        )
    }

    private func validateWaiver(
        _ waiver: SignoffWaiver,
        request: SignoffRequest,
        records: [ReleaseSignoffEvidenceReference]
    ) -> (isValid: Bool, diagnostics: [XcircuiteEngineDiagnostic]) {
        var diagnostics: [XcircuiteEngineDiagnostic] = []
        func fail(_ code: String, _ message: String) {
            diagnostics.append(diagnostic(code, message, entity: waiver.waiverID))
        }
        let affected = records.filter { waiver.affectedEvidenceIDs.contains($0.evidenceID) }
        if waiver.waiverID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail("WAIVER_ID_REQUIRED", "Waiver ID must not be empty.") }
        if waiver.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail("WAIVER_REASON_REQUIRED", "Waiver reason must not be empty.") }
        if waiver.authority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail("WAIVER_AUTHORITY_REQUIRED", "Waiver authority must not be empty.") }
        if waiver.affectedEvidenceIDs.isEmpty { fail("WAIVER_SCOPE_REQUIRED", "A waiver must identify affected evidence IDs.") }
        if waiver.expiresAt <= waiver.approvedAt || waiver.expiresAt <= now() { fail("WAIVER_EXPIRED_OR_INVALID", "Waiver expiry must be after approval and in the future.") }
        if waiver.designDigest != request.designDigest { fail("WAIVER_DESIGN_DIGEST_MISMATCH", "Waiver is bound to a different design revision.") }
        if waiver.pdkDigest != request.pdkDigest { fail("WAIVER_PDK_DIGEST_MISMATCH", "Waiver is bound to a different PDK revision.") }
        if affected.count != waiver.affectedEvidenceIDs.count { fail("WAIVER_EVIDENCE_NOT_FOUND", "Waiver scope contains an evidence ID that is not present in the request.") }
        if affected.contains(where: { $0.axis != waiver.axis }) { fail("WAIVER_AXIS_MISMATCH", "Waiver scope contains evidence from another signoff axis.") }
        if (waiver.toolID == nil) != (waiver.toolDigest == nil) { fail("WAIVER_TOOL_SCOPE_INCOMPLETE", "Waiver tool scope must provide both tool ID and tool digest, or neither.") }
        if let toolID = waiver.toolID, affected.contains(where: { $0.toolID != toolID }) { fail("WAIVER_TOOL_SCOPE_MISMATCH", "Waiver tool scope does not match affected evidence.") }
        if let toolDigest = waiver.toolDigest, affected.contains(where: { $0.toolDigest != toolDigest }) { fail("WAIVER_TOOL_DIGEST_MISMATCH", "Waiver tool digest scope does not match affected evidence.") }
        return (diagnostics.isEmpty, diagnostics)
    }

    private func makeEvidenceDigest(_ records: [ReleaseSignoffEvidenceReference]) -> String {
        let material = records.sorted { $0.evidenceID < $1.evidenceID }.map {
            [$0.evidenceID, $0.axis.rawValue, $0.artifact.path, $0.artifact.sha256 ?? "", $0.designDigest, $0.pdkDigest, $0.toolID, $0.toolDigest].joined(separator: "|")
        }.joined(separator: "\n")
        return XcircuiteHasher().sha256(data: Data(material.utf8))
    }

    private func uniqueArtifacts(_ artifacts: [XcircuiteFileReference]) -> [XcircuiteFileReference] {
        Array(Set(artifacts)).sorted { $0.path < $1.path }
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
        }
    }

    private func diagnostic(_ code: String, _ message: String, entity: String?) -> XcircuiteEngineDiagnostic {
        XcircuiteEngineDiagnostic(
            severity: .error,
            code: code,
            message: message,
            entity: entity,
            suggestedActions: ["inspect_release_contract", "retain_or_rebuild_required_evidence"]
        )
    }

    private func envelope(
        request: SignoffRequest,
        status: XcircuiteEngineExecutionStatus,
        diagnostics: [XcircuiteEngineDiagnostic],
        artifacts: [XcircuiteFileReference],
        metadata: XcircuiteEngineExecutionMetadata,
        payload: SignoffPayload
    ) -> XcircuiteEngineResultEnvelope<SignoffPayload> {
        XcircuiteEngineResultEnvelope(
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
        metadata: XcircuiteEngineExecutionMetadata,
        diagnostics: [XcircuiteEngineDiagnostic]
    ) -> XcircuiteEngineResultEnvelope<SignoffPayload> {
        envelope(
            request: request,
            status: .blocked,
            diagnostics: diagnostics,
            artifacts: [],
            metadata: metadata,
            payload: SignoffPayload(
                approved: false,
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
