import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore
import ToolQualification

public struct DefaultReleaseAuthorizer: ReleaseAuthorizing {
    private let qualificationEngine: any ToolQualificationEngine
    private let artifactReader: any ReleaseArtifactReading

    public init(
        qualificationEngine: any ToolQualificationEngine,
        artifactReader: any ReleaseArtifactReading
    ) {
        self.qualificationEngine = qualificationEngine
        self.artifactReader = artifactReader
    }

    public func execute(_ request: ReleaseAuthorizationRequest) async throws -> ReleaseAuthorizationResult {
        var diagnostics: [DesignDiagnostic] = []
        let provenance = try ExecutionProvenance(
            engineID: "release.authorization",
            implementationID: "native.release.authorization",
            implementationVersion: "1.0.0",
            startedAt: request.evaluatedAt,
            completedAt: request.evaluatedAt
        )

        validateApproval(request, diagnostics: &diagnostics)
        diagnostics.append(contentsOf: await validateTrust(request))
        diagnostics.append(contentsOf: await validateBundle(request))

        let blocked = diagnostics.contains { $0.severity == .error }
        return ReleaseAuthorizationResult(
            status: blocked ? .blocked : .authorized,
            signoffBundle: blocked ? nil : request.signoffBundle,
            diagnostics: diagnostics,
            provenance: provenance
        )
    }

    private func validateApproval(
        _ request: ReleaseAuthorizationRequest,
        diagnostics: inout [DesignDiagnostic]
    ) {
        guard request.approval.runID == request.runID,
              request.approval.stageID == request.stageID else {
            diagnostics.append(diagnostic("RELEASE_APPROVAL_SCOPE_MISMATCH", "Approval does not bind the requested run and release stage."))
            return
        }
        guard request.approval.verdict == .approved else {
            diagnostics.append(diagnostic("RELEASE_APPROVAL_REJECTED", "The release stage was not approved."))
            return
        }
        guard request.approval.reviewerKind == .human,
              !request.approval.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            diagnostics.append(diagnostic("HUMAN_RELEASE_APPROVAL_REQUIRED", "Release requires an identified human reviewer."))
            return
        }
        guard request.approval.createdAt <= request.evaluatedAt else {
            diagnostics.append(diagnostic("RELEASE_APPROVAL_TIMESTAMP_INVALID", "Approval time is later than the authorization evaluation time."))
            return
        }
        guard request.approval.evidence.stageResult == request.signoffBundle.artifact else {
            diagnostics.append(diagnostic("RELEASE_APPROVAL_EVIDENCE_MISMATCH", "Approval is not bound to the exact signoff bundle artifact."))
            return
        }
    }

    private func validateTrust(_ request: ReleaseAuthorizationRequest) async -> [DesignDiagnostic] {
        var diagnostics: [DesignDiagnostic] = []
        let required = Set(request.requiredToolIDs)
        guard !required.isEmpty, required.count == request.requiredToolIDs.count,
              request.requiredToolIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            diagnostics.append(diagnostic("RELEASE_REQUIRED_TOOLS_INVALID", "Release must declare a nonempty, unique set of required tool identifiers."))
            return diagnostics
        }
        let grouped = Dictionary(grouping: request.toolTrustDecisions, by: \.toolID)
        let qualificationRequests = Dictionary(grouping: request.toolQualificationRequests, by: { $0.descriptor.toolID })
        let duplicateIDs = grouped.filter { $0.value.count != 1 }.keys
        if !duplicateIDs.isEmpty {
            diagnostics.append(diagnostic("RELEASE_TOOL_TRUST_DUPLICATED", "A required tool has more than one trust decision."))
        }
        for toolID in required.sorted() {
            guard let decision = grouped[toolID]?.first,
                  let qualificationRequest = qualificationRequests[toolID]?.only else {
                diagnostics.append(diagnostic("RELEASE_TOOL_TRUST_MISSING", "No trust decision exists for required tool \(toolID)."))
                continue
            }
            guard qualificationRequest.evaluatedAt <= request.evaluatedAt else {
                diagnostics.append(diagnostic("RELEASE_TOOL_TRUST_TIMESTAMP_INVALID", "Tool qualification for \(toolID) was evaluated after the release authorization time."))
                continue
            }
            let reevaluation = ToolQualificationRequest(
                descriptor: qualificationRequest.descriptor,
                requirement: qualificationRequest.requirement,
                health: qualificationRequest.health,
                inputs: qualificationRequest.inputs,
                evaluatedAt: request.evaluatedAt
            )
            let result: ToolQualificationResult
            do {
                result = try await qualificationEngine.execute(reevaluation)
            } catch {
                diagnostics.append(diagnostic("RELEASE_TOOL_TRUST_REEVALUATION_FAILED", error.localizedDescription))
                continue
            }
            if decision != result.decision {
                diagnostics.append(diagnostic("RELEASE_TOOL_TRUST_DECISION_MISMATCH", "The retained trust decision for \(toolID) does not match independently recomputed ToolQualification output."))
            } else if decision.status != .eligible {
                diagnostics.append(diagnostic("RELEASE_TOOL_NOT_TRUSTED", "Required tool \(toolID) is not eligible for this release."))
            }
        }
        return diagnostics
    }

    private func validateBundle(_ request: ReleaseAuthorizationRequest) async -> [DesignDiagnostic] {
        var diagnostics: [DesignDiagnostic] = []
        do {
            let data = try await artifactReader.verifiedData(for: request.signoffBundle.artifact)
            let bundle = try SignoffBundle.decodeCanonical(from: data)
            let axes = bundle.axisResults.map(\.axis)
            guard bundle.designDigest == request.signoffBundle.designDigest,
                  bundle.pdkDigest == request.signoffBundle.pdkDigest,
                  bundle.finalLayoutDigest == request.signoffBundle.finalLayoutDigest,
                  axes.count == ReleaseSignoffAxis.allCases.count,
                  Set(axes) == Set(ReleaseSignoffAxis.allCases),
                  bundle.axisResults.allSatisfy({ $0.disposition.isReleaseEligible }) else {
                diagnostics.append(diagnostic("RELEASE_BUNDLE_CONTENT_MISMATCH", "The retained bundle does not match its reference or contains an ineligible signoff axis."))
                return diagnostics
            }
        } catch {
            diagnostics.append(diagnostic("RELEASE_BUNDLE_READ_FAILED", error.localizedDescription))
        }
        return diagnostics
    }

    private func diagnostic(_ code: String, _ detail: String) -> DesignDiagnostic {
        DesignDiagnostic(
            code: .trusted(code),
            severity: .error,
            summary: "Release authorization blocked.",
            detail: detail
        )
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
