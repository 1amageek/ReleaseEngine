import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore
import SignoffEngine
import ToolQualification

public struct DefaultReleaseAuthorizer: ReleaseAuthorizing {
    private let qualificationEngine: any ToolQualificationEngine
    private let artifactReader: any ReleaseArtifactReading
    private let profileProvider: any SignoffProfileProviding
    private let evidenceValidator: any SignoffEvidenceValidating
    private let evidenceDigester: any SignoffEvidenceDigesting
    private let now: @Sendable () -> Date

    public init(
        qualificationEngine: any ToolQualificationEngine,
        artifactReader: any ReleaseArtifactReading,
        profileProvider: any SignoffProfileProviding = DefaultSignoffProfileProvider(),
        evidenceValidator: any SignoffEvidenceValidating = DefaultSignoffEvidenceValidator(),
        evidenceDigester: any SignoffEvidenceDigesting = CanonicalSignoffEvidenceDigester(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.qualificationEngine = qualificationEngine
        self.artifactReader = artifactReader
        self.profileProvider = profileProvider
        self.evidenceValidator = evidenceValidator
        self.evidenceDigester = evidenceDigester
        self.now = now
    }

    public func execute(_ request: ReleaseAuthorizationRequest) async throws -> ReleaseAuthorizationResult {
        let startedAt = now()
        var diagnostics: [DesignDiagnostic] = []

        if request.schemaVersion != ReleaseAuthorizationRequest.currentSchemaVersion {
            diagnostics.append(diagnostic(
                "RELEASE_AUTHORIZATION_SCHEMA_UNSUPPORTED",
                "Release authorization request schema is not supported."
            ))
        }

        if request.evaluatedAt > startedAt {
            diagnostics.append(diagnostic(
                "RELEASE_EVALUATION_TIMESTAMP_INVALID",
                "Release authorization cannot evaluate trust, approval, or waivers at a future time."
            ))
        }

        diagnostics.append(contentsOf: await validateApproval(request))
        let bundleValidation = await validateBundle(request)
        diagnostics.append(contentsOf: bundleValidation.diagnostics)
        if let bundle = bundleValidation.bundle {
            diagnostics.append(contentsOf: await validateTrust(request, bundle: bundle))
        }

        let blocked = diagnostics.contains { $0.severity == .error }
        let retainedBundleEvidence = bundleValidation.bundle?.evidenceArtifacts ?? []
        let retainedOperationalInputs = bundleValidation.bundle?.evidenceRecords.flatMap {
            let qualification = $0.processQualification
            return $0.inputArtifacts
                + qualification.identityArtifacts.all
                + qualification.evidenceArtifacts
                + qualification.inputArtifacts
                + qualification.outputArtifacts
        } ?? []
        let provenanceInputs = Array(Set(
            [
                request.signoffBundle.artifact,
                request.approval.evidence.plan,
            ] + retainedBundleEvidence
                + retainedOperationalInputs
                + request.toolQualificationRequests.flatMap(\.inputs)
        )).sorted { $0.id.rawValue < $1.id.rawValue }
        let provenance = try ExecutionProvenance(
            producer: ProducerIdentity(
                kind: .engine,
                identifier: "native.release.authorization",
                version: "2.0.0",
                build: ReleaseRuntimeIdentity.currentExecutableDigest()
            ),
            inputs: provenanceInputs,
            invocation: ExecutionInvocation.inProcess(
                entryPoint: "ReleaseEngine.DefaultReleaseAuthorizer.execute"
            ),
            environment: try ReleaseRuntimeIdentity.environmentFingerprint(
                toolchain: "native.release.authorization-2.0.0"
            ),
            startedAt: startedAt,
            completedAt: now()
        )
        return ReleaseAuthorizationResult(
            status: blocked ? .blocked : .authorized,
            signoffBundle: blocked ? nil : request.signoffBundle,
            approval: request.approval,
            diagnostics: diagnostics,
            provenance: provenance
        )
    }

    private func validateApproval(
        _ request: ReleaseAuthorizationRequest
    ) async -> [DesignDiagnostic] {
        guard request.approval.runID == request.runID,
              request.approval.stageID == request.stageID else {
            return [diagnostic("RELEASE_APPROVAL_SCOPE_MISMATCH", "Approval does not bind the requested run and release stage.")]
        }
        guard request.approval.verdict == .approved else {
            return [diagnostic("RELEASE_APPROVAL_REJECTED", "The release stage was not approved.")]
        }
        guard request.approval.reviewerKind == .human,
              !request.approval.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [diagnostic("HUMAN_RELEASE_APPROVAL_REQUIRED", "Release requires an identified human reviewer.")]
        }
        guard request.approval.createdAt <= request.evaluatedAt else {
            return [diagnostic("RELEASE_APPROVAL_TIMESTAMP_INVALID", "Approval time is later than the authorization evaluation time.")]
        }
        guard request.approval.evidence.stageResult == request.signoffBundle.artifact else {
            return [diagnostic("RELEASE_APPROVAL_EVIDENCE_MISMATCH", "Approval is not bound to the exact signoff bundle artifact.")]
        }
        do {
            _ = try await artifactReader.verifiedData(for: request.approval.evidence.plan)
        } catch {
            return [diagnostic(
                "RELEASE_APPROVAL_PLAN_EVIDENCE_FAILED",
                "The human approval plan artifact failed integrity verification: \(error.localizedDescription)"
            )]
        }
        return []
    }

    private func validateTrust(
        _ request: ReleaseAuthorizationRequest,
        bundle: SignoffBundle
    ) async -> [DesignDiagnostic] {
        var diagnostics: [DesignDiagnostic] = []
        let requiredScopes = Set(bundle.toolQualificationScopes)
        let requiredToolIDs = Set(requiredScopes.map(\.implementationID))
        guard !requiredScopes.isEmpty,
              requiredScopes.allSatisfy({
                  $0.isCompleteForProduction
                      && $0.pdkDigest?.caseInsensitiveCompare(bundle.pdkDigest) == .orderedSame
              }) else {
            diagnostics.append(diagnostic(
                "RELEASE_BUNDLE_TOOL_SCOPE_INVALID",
                "The signoff bundle must retain complete production qualification scopes bound to its exact PDK digest."
            ))
            return diagnostics
        }
        guard Set(request.requiredToolIDs) == requiredToolIDs,
              request.requiredToolIDs.count == requiredToolIDs.count else {
            diagnostics.append(diagnostic(
                "RELEASE_REQUIRED_TOOLS_MISMATCH",
                "The required tool inventory must exactly match the producer tools retained by the signoff bundle."
            ))
            return diagnostics
        }

        let decisionsByToolID = Dictionary(grouping: request.toolTrustDecisions, by: \.toolID)
        guard Set(decisionsByToolID.keys) == requiredToolIDs,
              decisionsByToolID.values.allSatisfy({ $0.count == 1 }) else {
            diagnostics.append(diagnostic(
                "RELEASE_TOOL_TRUST_INVENTORY_MISMATCH",
                "Release requires exactly one retained trust decision for every signoff producer tool and no unrelated decisions."
            ))
            return diagnostics
        }

        let requestScopes = request.toolQualificationRequests.compactMap {
            $0.descriptor.trustProfile.processQualification?.scope
        }
        guard requestScopes.count == request.toolQualificationRequests.count,
              requestScopes.count == Set(requestScopes).count,
              Set(requestScopes) == requiredScopes else {
            diagnostics.append(diagnostic(
                "RELEASE_TOOL_QUALIFICATION_SCOPE_MISMATCH",
                "Qualification requests must exactly reproduce every production scope retained by the signoff bundle."
            ))
            return diagnostics
        }

        for qualificationRequest in request.toolQualificationRequests {
            let toolID = qualificationRequest.descriptor.toolID
            guard let decision = decisionsByToolID[toolID]?.first,
                  let processQualification = qualificationRequest.descriptor.trustProfile.processQualification else {
                diagnostics.append(diagnostic("RELEASE_TOOL_TRUST_MISSING", "No trust decision exists for required tool \(toolID)."))
                continue
            }
            guard qualificationRequest.requirement.minimumLevel == .productionEligible,
                  qualificationRequest.descriptor.trustProfile.level == .productionEligible,
                  qualificationRequest.requirement.qualificationScope == processQualification.scope,
                  qualificationRequest.requirement.requireIndependentQualificationEvidence else {
                diagnostics.append(diagnostic(
                    "RELEASE_PRODUCTION_QUALIFICATION_REQUIRED",
                    "Release authorization requires an explicit production-eligible requirement bound to the exact independently qualified process scope for \(toolID)."
                ))
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

    private func validateBundle(
        _ request: ReleaseAuthorizationRequest
    ) async -> (bundle: SignoffBundle?, diagnostics: [DesignDiagnostic]) {
        var diagnostics: [DesignDiagnostic] = []
        do {
            let data = try await artifactReader.verifiedData(for: request.signoffBundle.artifact)
            let bundle = try SignoffBundle.decodeCanonical(from: data)
            let axes = bundle.axisResults.map(\.axis)
            guard request.signoffBundle.artifact.producer?.kind == .engine,
                  request.signoffBundle.artifact.producer?.identifier == "native.release.signoff",
                  request.signoffBundle.artifact.producer?.version == "2.0.0",
                  isSHA256(request.signoffBundle.artifact.producer?.build),
                  bundle.designDigest == request.signoffBundle.designDigest,
                  bundle.pdkDigest == request.signoffBundle.pdkDigest,
                  bundle.finalLayoutDigest == request.signoffBundle.finalLayoutDigest,
                  axes.count == ReleaseSignoffAxis.allCases.count,
                  Set(axes) == Set(ReleaseSignoffAxis.allCases),
                  bundle.axisResults.allSatisfy({ $0.disposition.isReleaseEligible }),
                  bundle.issuedAt <= request.evaluatedAt,
                  bundle.waiversAreValid(at: request.evaluatedAt) else {
                diagnostics.append(diagnostic("RELEASE_BUNDLE_CONTENT_MISMATCH", "The retained bundle does not match its reference or contains an ineligible signoff axis."))
                return (nil, diagnostics)
            }
            guard !bundle.evidenceRecords.isEmpty,
                  Set(bundle.evidenceRecords.map(\.artifact)) == Set(bundle.evidenceArtifacts),
                  Set(bundle.evidenceRecords.map(\.processQualification.scope))
                    == Set(bundle.toolQualificationScopes),
                  try evidenceDigester.digest(bundle.evidenceRecords)
                    .caseInsensitiveCompare(bundle.evidenceDigest) == .orderedSame else {
                diagnostics.append(diagnostic(
                    "RELEASE_BUNDLE_EVIDENCE_BINDING_INVALID",
                    "The signoff bundle must retain canonical typed evidence records whose digest, artifacts, and qualification scopes match the bundle."
                ))
                return (nil, diagnostics)
            }
            guard let profile = profileProvider.profile(profileID: bundle.profileID) else {
                diagnostics.append(diagnostic(
                    "RELEASE_BUNDLE_PROFILE_INVALID",
                    "The signoff bundle references an unknown signoff profile."
                ))
                return (nil, diagnostics)
            }
            let evidenceValidation = evidenceValidator.validate(
                evidence: bundle.evidenceRecords,
                projectRoot: request.projectRoot.map(URL.init(fileURLWithPath:)),
                designDigest: bundle.designDigest,
                pdkDigest: bundle.pdkDigest,
                profile: profile,
                evaluatedAt: request.evaluatedAt
            )
            diagnostics.append(contentsOf: evidenceValidation.diagnostics)
            guard evidenceValidation.blockedAxes.isEmpty,
                  evidenceValidation.blockedEvidenceIDs.isEmpty else {
                return (nil, diagnostics)
            }
            for evidenceArtifact in bundle.evidenceArtifacts {
                do {
                    _ = try await artifactReader.verifiedData(for: evidenceArtifact)
                } catch {
                    diagnostics.append(diagnostic(
                        "RELEASE_EVIDENCE_READ_FAILED",
                        "Retained signoff evidence failed integrity verification: \(error.localizedDescription)"
                    ))
                }
            }
            guard diagnostics.isEmpty else {
                return (nil, diagnostics)
            }
            return (bundle, diagnostics)
        } catch {
            diagnostics.append(diagnostic("RELEASE_BUNDLE_READ_FAILED", error.localizedDescription))
            return (nil, diagnostics)
        }
    }

    private func diagnostic(_ code: String, _ detail: String) -> DesignDiagnostic {
        DesignDiagnostic(
            code: .trusted(code),
            severity: .error,
            summary: "Release authorization blocked.",
            detail: detail
        )
    }

    private func isSHA256(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }

}
