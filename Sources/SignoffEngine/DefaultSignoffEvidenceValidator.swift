import Foundation
import ReleaseCore
import ToolQualification
import XcircuitePackage

public struct DefaultSignoffEvidenceValidator: SignoffEvidenceValidating {
    private let verifier: XcircuiteFileReferenceVerifier

    public init(verifier: XcircuiteFileReferenceVerifier = XcircuiteFileReferenceVerifier()) {
        self.verifier = verifier
    }

    public func validate(
        evidence: [ReleaseSignoffEvidenceReference],
        projectRoot: URL?,
        designDigest: String,
        pdkDigest: String,
        profile: ReleaseSignoffProfile
    ) -> SignoffEvidenceValidationResult {
        var verifiedIDs: [String] = []
        var blockedIDs: [String] = []
        var blockedAxes = Set<ReleaseSignoffAxis>()
        var codesByAxis: [ReleaseSignoffAxis: [String]] = [:]
        var diagnostics: [XcircuiteEngineDiagnostic] = []
        var seenIDs = Set<String>()

        func add(
            _ code: String,
            _ message: String,
            axis: ReleaseSignoffAxis?,
            entity: String?
        ) {
            diagnostics.append(XcircuiteEngineDiagnostic(
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
            if !isSHA256(record.designDigest) || !isSHA256(record.pdkDigest) || !isSHA256(record.toolDigest) {
                recordBlocked = true
                add("INVALID_PROVENANCE_DIGEST", "Design, PDK and tool provenance digests must be SHA-256 values.", axis: axis, entity: record.evidenceID)
            }
            if record.toolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recordBlocked = true
                add("TOOL_ID_REQUIRED", "Evidence must identify the producing tool.", axis: axis, entity: record.evidenceID)
            }
            if record.qualificationLevel < requirement.minimumQualificationLevel {
                recordBlocked = true
                add(
                    "INSUFFICIENT_TOOL_QUALIFICATION",
                    "Evidence qualification level is below the profile threshold.",
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
                let integrity = verifier.verify(record.artifact, projectRoot: projectRoot)
                if integrity.status != .verified {
                    recordBlocked = true
                    add(
                        "EVIDENCE_ARTIFACT_INTEGRITY_FAILED",
                        integrity.message,
                        axis: axis,
                        entity: record.evidenceID
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

    private func suggestedActions(for code: String) -> [String] {
        switch code {
        case "EVIDENCE_PROJECT_ROOT_REQUIRED":
            ["provide_project_root", "resolve_project_relative_artifacts"]
        case "EVIDENCE_ARTIFACT_INTEGRITY_FAILED":
            ["recompute_artifact_digest", "rerun_signoff_stage"]
        case "INSUFFICIENT_TOOL_QUALIFICATION":
            ["retain_corpus_evidence", "qualify_tool_for_process"]
        case "DESIGN_DIGEST_MISMATCH", "PDK_DIGEST_MISMATCH":
            ["rerun_all_signoff_axes_for_same_revision"]
        default:
            ["inspect_signoff_request", "retain_structured_evidence"]
        }
    }
}
