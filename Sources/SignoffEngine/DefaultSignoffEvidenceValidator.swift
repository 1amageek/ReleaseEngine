import Foundation
import ReleaseCore
import ToolQualification
import CircuiteFoundation

public struct DefaultSignoffEvidenceValidator: SignoffEvidenceValidating {
    private let verifier: LocalArtifactVerifier

    public init(verifier: LocalArtifactVerifier = LocalArtifactVerifier()) {
        self.verifier = verifier
    }

    public func validate(
        evidence: [ReleaseSignoffEvidenceReference],
        projectRoot: URL?,
        designDigest: String,
        pdkDigest: String,
        profile: ReleaseSignoffProfile,
        evaluatedAt: Date
    ) -> SignoffEvidenceValidationResult {
        var verifiedIDs: [String] = []
        var blockedIDs: [String] = []
        var blockedAxes = Set<ReleaseSignoffAxis>()
        var codesByAxis: [ReleaseSignoffAxis: [String]] = [:]
        var diagnostics: [DesignDiagnostic] = []
        var seenIDs = Set<String>()

        func add(
            _ code: String,
            _ message: String,
            axis: ReleaseSignoffAxis?,
            entity: String?
        ) {
            diagnostics.append(DesignDiagnostic(
                severity: .error,
                code: code,
                message: message,
                entity: entity,
                suggestedActions: suggestedActions(for: code)
            ))
            if let axis {
                blockedAxes.insert(axis)
                codesByAxis[axis, default: []].append(code)
            }
        }

        guard !evidence.isEmpty else {
            for requirement in profile.requirements where requirement.required {
                add(
                    "EVIDENCE_RECORDS_REQUIRED",
                    "No typed signoff evidence records were supplied for the release profile.",
                    axis: requirement.axis,
                    entity: requirement.axis.rawValue
                )
            }
            return SignoffEvidenceValidationResult(
                blockedAxes: profile.requirements.filter(\.required).map(\.axis),
                diagnosticCodesByAxis: codesByAxis,
                diagnostics: diagnostics
            )
        }

        guard let projectRoot else {
            for record in evidence {
                blockedIDs.append(record.evidenceID)
                add(
                    "EVIDENCE_PROJECT_ROOT_REQUIRED",
                    "A project root is required to verify the immutable evidence artifact.",
                    axis: record.axis,
                    entity: record.evidenceID
                )
            }
            return SignoffEvidenceValidationResult(
                blockedEvidenceIDs: blockedIDs,
                blockedAxes: Array(blockedAxes).sorted(),
                diagnosticCodesByAxis: codesByAxis,
                diagnostics: diagnostics
            )
        }

        for record in evidence {
            let axis = record.axis
            let requirement = profile.requirement(for: axis)
            if seenIDs.contains(record.evidenceID) {
                blockedIDs.append(record.evidenceID)
                add(
                    "DUPLICATE_EVIDENCE_ID",
                    "Evidence IDs must be unique within a signoff request.",
                    axis: axis,
                    entity: record.evidenceID
                )
                continue
            }
            seenIDs.insert(record.evidenceID)

            guard let requirement else {
                blockedIDs.append(record.evidenceID)
                add(
                    "UNSUPPORTED_SIGNOFF_AXIS",
                    "Evidence references an axis that is not declared by the selected profile.",
                    axis: axis,
                    entity: record.evidenceID
                )
                continue
            }

            var recordBlocked = false
            if record.evidenceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recordBlocked = true
                add("EVIDENCE_ID_REQUIRED", "Evidence ID must not be empty.", axis: axis, entity: nil)
            }
            if record.designDigest != designDigest {
                recordBlocked = true
                add("DESIGN_DIGEST_MISMATCH", "Evidence was produced from a different design revision.", axis: axis, entity: record.evidenceID)
            }
            if record.pdkDigest != pdkDigest {
                recordBlocked = true
                add("PDK_DIGEST_MISMATCH", "Evidence was produced from a different PDK revision.", axis: axis, entity: record.evidenceID)
            }
            if !isSHA256(record.designDigest) || !isSHA256(record.pdkDigest) || !isSHA256(record.toolBinaryDigest) {
                recordBlocked = true
                add("INVALID_PROVENANCE_DIGEST", "Design, PDK and tool provenance digests must be SHA-256 values.", axis: axis, entity: record.evidenceID)
            }
            if record.toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || record.toolVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recordBlocked = true
                add("TOOL_IDENTITY_REQUIRED", "Evidence must identify the producing tool and exact version.", axis: axis, entity: record.evidenceID)
            }
            let executionIdentities = [record.executionProvenance.producer]
                + record.executionProvenance.supportingTools
            if !executionIdentities.contains(where: {
                matchesQualifiedImplementation(
                    $0,
                    implementationID: record.toolID,
                    version: record.toolVersion,
                    binaryDigest: record.toolBinaryDigest
                )
            }) {
                recordBlocked = true
                add(
                    "OPERATIONAL_EXECUTION_IDENTITY_MISMATCH",
                    "Execution provenance must bind the exact qualified implementation identifier, version, and executable digest.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            if record.artifact.producer.map({ executionIdentities.contains($0) }) != true {
                recordBlocked = true
                add(
                    "OPERATIONAL_ARTIFACT_PROVENANCE_MISMATCH",
                    "The operational result artifact producer must be retained by its execution provenance.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            if Set(record.executionProvenance.inputs) != Set(record.inputArtifacts) {
                recordBlocked = true
                add(
                    "OPERATIONAL_EXECUTION_INPUT_MISMATCH",
                    "Execution provenance inputs must exactly match the immutable operational inputs declared by the signoff evidence.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            if record.executionProvenance.completedAt > evaluatedAt {
                recordBlocked = true
                add(
                    "OPERATIONAL_EXECUTION_TIMESTAMP_INVALID",
                    "Operational evidence cannot complete after the signoff evaluation time.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            if record.disposition == .blocked {
                recordBlocked = true
                add(
                    "EVIDENCE_REPORTED_BLOCKED",
                    "The producing analysis explicitly reported that this signoff evidence is blocked.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            let dispositionReason = record.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            if record.disposition != .passed,
               dispositionReason == nil || dispositionReason == "" {
                recordBlocked = true
                add(
                    "EVIDENCE_DISPOSITION_REASON_REQUIRED",
                    "Failed or blocked signoff evidence must retain a non-empty reason.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            let qualification = record.processQualification
            if requirement.minimumQualificationLevel == .productionEligible,
               !qualification.isQualified(at: evaluatedAt, requirePDKScope: true) {
                recordBlocked = true
                add(
                    "PROCESS_QUALIFICATION_INVALID",
                    "Evidence requires a fresh, independently qualified, artifact-backed production record.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            if qualification.toolID != record.toolID
                || qualification.scope.implementationID != record.toolID
                || qualification.scope.toolVersion != record.toolVersion
                || qualification.scope.binaryDigest.caseInsensitiveCompare(record.toolBinaryDigest) != .orderedSame
                || qualification.scope.pdkDigest?.caseInsensitiveCompare(record.pdkDigest) != .orderedSame {
                recordBlocked = true
                add(
                    "PROCESS_QUALIFICATION_SCOPE_MISMATCH",
                    "Qualification must bind the exact tool binary/version, process, PDK, deck, and independent oracle scope.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            if qualification.identityArtifacts.toolExecutable.producer?.kind != .tool
                || qualification.identityArtifacts.toolExecutable.producer?.identifier != record.toolID
                || qualification.identityArtifacts.toolExecutable.producer?.version != record.toolVersion
                || qualification.identityArtifacts.toolExecutable.digest.hexadecimalValue.caseInsensitiveCompare(
                    record.toolBinaryDigest
                ) != .orderedSame {
                recordBlocked = true
                add(
                    "QUALIFIED_TOOL_BINARY_MISMATCH",
                    "Operational evidence must bind the exact executable artifact qualified for the producer tool and version.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            if record.inputArtifacts.isEmpty
                || !record.inputArtifacts.contains(where: {
                    $0.digest.algorithm == .sha256
                        && $0.digest.hexadecimalValue.caseInsensitiveCompare(
                            record.designDigest
                        ) == .orderedSame
                })
                || !record.inputArtifacts.contains(where: {
                    $0.digest.algorithm == .sha256
                        && $0.digest.hexadecimalValue.caseInsensitiveCompare(
                            record.pdkDigest
                        ) == .orderedSame
                }) {
                recordBlocked = true
                add(
                    "SIGNOFF_INPUT_BINDING_INCOMPLETE",
                    "Evidence must retain immutable design and PDK input artifacts.",
                    axis: axis,
                    entity: record.evidenceID
                )
            }
            if !requirement.requiredArtifactKinds.isEmpty,
               !requirement.requiredArtifactKinds.contains(record.artifact.kind) {
                recordBlocked = true
                add("UNEXPECTED_EVIDENCE_ARTIFACT_KIND", "Evidence artifact kind is not accepted by the selected signoff axis.", axis: axis, entity: record.evidenceID)
            }
            if record.artifact.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recordBlocked = true
                add("EVIDENCE_PATH_REQUIRED", "Evidence artifact path must be project-relative and non-empty.", axis: axis, entity: record.evidenceID)
            } else {
                let integrity = verifier.verify(record.artifact, relativeTo: projectRoot)
                if !integrity.isVerified {
                    recordBlocked = true
                    add(
                        "EVIDENCE_ARTIFACT_INTEGRITY_FAILED",
                        integrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; "),
                        axis: axis,
                        entity: record.evidenceID
                    )
                }
            }
            for inputArtifact in record.inputArtifacts {
                let integrity = verifier.verify(inputArtifact, relativeTo: projectRoot)
                if !integrity.isVerified {
                    recordBlocked = true
                    add(
                        "SIGNOFF_INPUT_ARTIFACT_INTEGRITY_FAILED",
                        integrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; "),
                        axis: axis,
                        entity: inputArtifact.path
                    )
                }
            }
            let qualificationArtifacts = qualification.identityArtifacts.all
                + qualification.evidenceArtifacts
                + qualification.inputArtifacts
                + qualification.outputArtifacts
            for retainedArtifact in Set(qualificationArtifacts) {
                let integrity = verifier.verify(retainedArtifact, relativeTo: projectRoot)
                if !integrity.isVerified {
                    recordBlocked = true
                    add(
                        "QUALIFICATION_ARTIFACT_INTEGRITY_FAILED",
                        integrity.issues.map { $0.detail ?? $0.code.rawValue }.joined(separator: "; "),
                        axis: axis,
                        entity: retainedArtifact.path
                    )
                }
            }
            if recordBlocked {
                blockedIDs.append(record.evidenceID)
            } else {
                verifiedIDs.append(record.evidenceID)
            }
        }

        return SignoffEvidenceValidationResult(
            verifiedEvidenceIDs: verifiedIDs.sorted(),
            blockedEvidenceIDs: blockedIDs.sorted(),
            blockedAxes: Array(blockedAxes).sorted(),
            diagnosticCodesByAxis: codesByAxis.mapValues { $0.sorted() },
            diagnostics: diagnostics
        )
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }

    private func matchesQualifiedImplementation(
        _ producer: ProducerIdentity,
        implementationID: String,
        version: String,
        binaryDigest: String
    ) -> Bool {
        producer.version == version
            && producer.identifier == implementationID
            && producer.build?.caseInsensitiveCompare(binaryDigest) == .orderedSame
    }

    private func suggestedActions(for code: String) -> [String] {
        switch code {
        case "EVIDENCE_PROJECT_ROOT_REQUIRED":
            ["provide_project_root", "resolve_project_relative_artifacts"]
        case "EVIDENCE_ARTIFACT_INTEGRITY_FAILED":
            ["recompute_artifact_digest", "rerun_signoff_stage"]
        case "PROCESS_QUALIFICATION_INVALID", "PROCESS_QUALIFICATION_SCOPE_MISMATCH":
            ["retain_corpus_evidence", "qualify_tool_for_process"]
        case "DESIGN_DIGEST_MISMATCH", "PDK_DIGEST_MISMATCH":
            ["rerun_all_signoff_axes_for_same_revision"]
        default:
            ["inspect_signoff_request", "retain_structured_evidence"]
        }
    }
}
