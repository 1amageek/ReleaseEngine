import CircuiteFoundation
import DesignFlowKernel
import Foundation
import ReleaseCore
import SignoffEngine
import ToolQualification

public struct DefaultReleaseAuthorizer: ReleaseAuthorizing {
    private let qualificationEngine: any ToolQualificationEngine
    private let artifactReader: any ReleaseAuthorizationArtifactReading
    private let approvalAuthenticator: any ReleaseApprovalAuthenticating
    private let profileProvider: any SignoffProfileProviding
    private let evidenceValidator: any SignoffEvidenceValidating
    private let evidenceDigester: any SignoffEvidenceDigesting
    private let exactBundleValidator: any ReleaseExactBundleValidating
    private let now: @Sendable () -> Date

    public init(
        qualificationEngine: any ToolQualificationEngine,
        artifactReader: any ReleaseAuthorizationArtifactReading,
        approvalAuthenticator: any ReleaseApprovalAuthenticating,
        profileProvider: any SignoffProfileProviding = DefaultSignoffProfileProvider(),
        evidenceValidator: any SignoffEvidenceValidating = DefaultSignoffEvidenceValidator(),
        evidenceDigester: any SignoffEvidenceDigesting = CanonicalSignoffEvidenceDigester(),
        exactBundleValidator: any ReleaseExactBundleValidating = DefaultReleaseExactBundleValidator(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.qualificationEngine = qualificationEngine
        self.artifactReader = artifactReader
        self.approvalAuthenticator = approvalAuthenticator
        self.profileProvider = profileProvider
        self.evidenceValidator = evidenceValidator
        self.evidenceDigester = evidenceDigester
        self.exactBundleValidator = exactBundleValidator
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

        diagnostics.append(contentsOf: validateExactBundle(request))
        diagnostics.append(contentsOf: validateArtifactBindings(request))
        diagnostics.append(contentsOf: await validateApproval(request))
        diagnostics.append(contentsOf: await validateQualificationRecords(request))
        let bundleValidation = await validateBundle(request)
        diagnostics.append(contentsOf: bundleValidation.diagnostics)
        if let bundle = bundleValidation.bundle {
            diagnostics.append(contentsOf: validateExactContentBindings(
                request,
                signoffBundle: bundle
            ))
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
                request.signoffBundle.artifact.reference,
                request.approval.evidence.plan.reference,
                request.approval.evidence.stageResult.reference,
            ] + retainedBundleEvidence
                + retainedOperationalInputs
                + request.approvalArtifacts.map(\.reference)
                + request.qualificationRecordArtifacts.map(\.reference)
                + request.toolQualificationRequests.flatMap(\.inputs)
        )).sorted { $0.id.description < $1.id.description }
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
        return try ReleaseAuthorizationResult(
            status: blocked ? .blocked : .authorized,
            signoffBundle: blocked ? nil : request.signoffBundle,
            exactReleaseBundle: blocked ? nil : request.exactReleaseBundle,
            approval: request.approval,
            diagnostics: diagnostics,
            provenance: provenance
        )
    }

    private func validateExactBundle(
        _ request: ReleaseAuthorizationRequest
    ) -> [DesignDiagnostic] {
        do {
            try exactBundleValidator.validate(request.exactReleaseBundle)
            return []
        } catch {
            return [diagnostic(
                "RELEASE_EXACT_BUNDLE_INVALID",
                "The exact release bundle is invalid: \(String(describing: error))"
            )]
        }
    }

    private func validateArtifactBindings(
        _ request: ReleaseAuthorizationRequest
    ) -> [DesignDiagnostic] {
        var diagnostics: [DesignDiagnostic] = []
        let releaseBindings = request.artifactBindings + [request.signoffBundle.artifact]
        let flowBindings = request.approvalArtifacts
            + request.qualificationRecordArtifacts
        let bindings = releaseBindings.map { ($0.reference, $0.availability) }
            + flowBindings.map { ($0.reference, $0.availability) }
        for group in Dictionary(grouping: bindings, by: { $0.0 }).values {
            if Set(group.map(\.1)).count != 1 {
                diagnostics.append(diagnostic(
                    "RELEASE_ARTIFACT_MATERIALIZATION_CONFLICT",
                    "One content identity cannot resolve to multiple materializations during authorization."
                ))
            }
        }
        if request.artifactBindings.map(\.reference).count
            != Set(request.artifactBindings.map(\.reference)).count {
            diagnostics.append(diagnostic(
                "RELEASE_ARTIFACT_BINDING_DUPLICATE",
                "Authorization artifact bindings must contain one exact availability per content identity."
            ))
        }
        if request.approvalArtifacts.map(\.reference).count
            != Set(request.approvalArtifacts.map(\.reference)).count {
            diagnostics.append(diagnostic(
                "RELEASE_APPROVAL_ARTIFACT_BINDING_DUPLICATE",
                "Approval record bindings must contain one exact availability per content identity."
            ))
        }
        if request.qualificationRecordArtifacts.map(\.reference).count
            != Set(request.qualificationRecordArtifacts.map(\.reference)).count {
            diagnostics.append(diagnostic(
                "RELEASE_QUALIFICATION_ARTIFACT_BINDING_DUPLICATE",
                "Qualification record bindings must contain one exact availability per content identity."
            ))
        }
        if request.additionalContentIdentities.count
            != Set(request.additionalContentIdentities).count {
            diagnostics.append(diagnostic(
                "RELEASE_ADDITIONAL_CONTENT_IDENTITY_DUPLICATE",
                "Additional release content identities must be unique."
            ))
        }
        return diagnostics
    }

    private func validateExactContentBindings(
        _ request: ReleaseAuthorizationRequest,
        signoffBundle: SignoffBundle
    ) -> [DesignDiagnostic] {
        let exactBundle = request.exactReleaseBundle
        let retainedContent = Set(exactBundle.contentIdentities)
        let approvalContent = Set(exactBundle.approvalContentIdentities)
        let qualificationContent = Set(exactBundle.qualificationContentIdentities)
        let requiredInventory = ReleaseExactContentInventory(
            signoffBundle: signoffBundle,
            signoffBundleReference: request.signoffBundle,
            approval: request.approval,
            approvalArtifacts: request.approvalArtifacts,
            toolQualificationRequests: request.toolQualificationRequests,
            qualificationRecordArtifacts: request.qualificationRecordArtifacts,
            additionalContentIdentities: request.additionalContentIdentities
        )
        let requiredApprovalContent = Set(
            requiredInventory.approvalContentIdentities
        )
        guard approvalContent == requiredApprovalContent else {
            return [diagnostic(
                "RELEASE_APPROVAL_CONTENT_IDENTITY_MISMATCH",
                "The exact release bundle approval inventory does not exactly match the content used by the approval."
            )]
        }
        let requiredQualificationContent = Set(
            requiredInventory.qualificationContentIdentities
        )
        guard qualificationContent == requiredQualificationContent else {
            return [diagnostic(
                "RELEASE_QUALIFICATION_CONTENT_IDENTITY_MISMATCH",
                "The exact release bundle qualification inventory does not exactly match the content used by production qualification."
            )]
        }
        let requiredContent = Set(requiredInventory.contentIdentities)
        guard requiredContent == retainedContent else {
            return [diagnostic(
                "RELEASE_CONTENT_IDENTITY_INVENTORY_MISMATCH",
                "The exact release bundle content inventory does not exactly match signoff, approval, qualification, and explicitly retained additional content."
            )]
        }
        return []
    }

    private func validateApproval(
        _ request: ReleaseAuthorizationRequest
    ) async -> [DesignDiagnostic] {
        guard request.approval.runID == request.runID,
              request.approval.stageID == request.stageID else {
            return [diagnostic(
                "RELEASE_APPROVAL_SCOPE_MISMATCH",
                "Approval does not bind the requested run and release stage."
            )]
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
        guard request.approvalArtifacts.count == 1,
              let approvalArtifact = request.approvalArtifacts.first else {
            return [diagnostic(
                "RELEASE_APPROVAL_RECORD_INVENTORY_INVALID",
                "Release authorization requires exactly one exact approval record artifact."
            )]
        }
        do {
            let data = try await artifactReader.verifiedData(for: approvalArtifact)
            let retainedApproval = try JSONDecoder().decode(
                FlowApprovalRecord.self,
                from: data
            )
            guard retainedApproval == request.approval else {
                return [diagnostic(
                    "RELEASE_APPROVAL_RECORD_MISMATCH",
                    "The retained approval record does not match the approval under authorization."
                )]
            }
        } catch {
            return [diagnostic(
                "RELEASE_APPROVAL_RECORD_READ_FAILED",
                "The retained approval record failed integrity or schema verification: \(error.localizedDescription)"
            )]
        }
        do {
            _ = try await artifactReader.verifiedData(for: request.approval.evidence.plan)
        } catch {
            return [diagnostic(
                "RELEASE_APPROVAL_PLAN_EVIDENCE_FAILED",
                "The human approval plan artifact failed integrity verification: \(error.localizedDescription)"
            )]
        }
        do {
            try await approvalAuthenticator.authenticate(
                approval: request.approval,
                runID: request.runID,
                signoffBundle: request.signoffBundle.artifact.reference,
                evaluatedAt: request.evaluatedAt
            )
        } catch {
            return [diagnostic(
                "RELEASE_APPROVAL_AUTHENTICATION_FAILED",
                "The human approval could not be authenticated against the canonical run ledger: \(error.localizedDescription)"
            )]
        }
        return []
    }

    private func validateQualificationRecords(
        _ request: ReleaseAuthorizationRequest
    ) async -> [DesignDiagnostic] {
        var recordsByToolID: [String: ToolQualificationRecord] = [:]
        for binding in request.qualificationRecordArtifacts {
            do {
                let data = try await artifactReader.verifiedData(for: binding)
                let record = try ToolQualificationRecord.decodeCanonical(from: data)
                guard recordsByToolID[record.descriptor.toolID] == nil else {
                    return [diagnostic(
                        "RELEASE_QUALIFICATION_RECORD_DUPLICATE_TOOL",
                        "Release authorization received multiple qualification records for one tool."
                    )]
                }
                recordsByToolID[record.descriptor.toolID] = record
            } catch {
                return [diagnostic(
                    "RELEASE_QUALIFICATION_RECORD_READ_FAILED",
                    "A retained qualification record failed integrity or schema verification: \(error.localizedDescription)"
                )]
            }
        }

        let requestsByToolID = Dictionary(
            grouping: request.toolQualificationRequests,
            by: { $0.descriptor.toolID }
        )
        guard requestsByToolID.values.allSatisfy({ $0.count == 1 }),
              Set(recordsByToolID.keys) == Set(requestsByToolID.keys) else {
            return [diagnostic(
                "RELEASE_QUALIFICATION_RECORD_INVENTORY_MISMATCH",
                "Qualification records must exactly cover the tools reevaluated for release."
            )]
        }
        for (toolID, requests) in requestsByToolID {
            guard let qualificationRequest = requests.first,
                  let record = recordsByToolID[toolID],
                  record.descriptor == qualificationRequest.descriptor,
                  qualificationRequest.health.map({ $0 == record.health }) ?? true,
                  record.issuedAt <= request.evaluatedAt else {
                return [diagnostic(
                    "RELEASE_QUALIFICATION_RECORD_MISMATCH",
                    "A qualification record does not match the exact tool evaluation input."
                )]
            }
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
            guard bundle.designDigest == request.signoffBundle.designDigest,
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
            guard case .local(_, let rootID, _) = request.signoffBundle.artifact.availability else {
                diagnostics.append(diagnostic(
                    "RELEASE_BUNDLE_AVAILABILITY_UNSUPPORTED",
                    "The managed-local release profile requires a local signoff bundle binding."
                ))
                return (nil, diagnostics)
            }
            let evidenceValidation = await evidenceValidator.validate(
                evidence: bundle.evidenceRecords,
                bindings: request.artifactBindings,
                projectRoot: request.projectRoot.map(URL.init(fileURLWithPath:)),
                rootID: rootID,
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
                    let binding = try requiredBinding(
                        for: evidenceArtifact,
                        in: request.artifactBindings
                    )
                    _ = try await artifactReader.verifiedData(for: binding)
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

    private func requiredBinding(
        for reference: ArtifactReference,
        in bindings: [ReleaseArtifactBinding]
    ) throws -> ReleaseArtifactBinding {
        let matches = bindings.filter { $0.reference == reference }
        guard matches.count == 1, let binding = matches.first else {
            throw ReleaseArtifactBindingError.missingBinding(reference.id)
        }
        return binding
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
