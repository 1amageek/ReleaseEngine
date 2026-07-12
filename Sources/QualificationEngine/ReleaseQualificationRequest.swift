import Foundation
import ReleaseCore
import ToolQualification
import XcircuitePackage

public struct ReleaseQualificationRequest: XcircuiteEngineRequest {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [XcircuiteFileReference]
    public var projectRoot: String?
    public var processProfileID: String
    public var suiteArtifact: XcircuiteFileReference
    public var qualificationReportArtifact: XcircuiteFileReference
    public var domainReportArtifacts: [XcircuiteFileReference]
    public var evidenceArtifacts: [XcircuiteFileReference]
    public var toolEvidence: [ToolEvidence]
    public var policy: ReleaseQualificationPolicy

    public init(
        runID: String,
        projectRoot: String?,
        processProfileID: String,
        suiteArtifact: XcircuiteFileReference,
        qualificationReportArtifact: XcircuiteFileReference,
        domainReportArtifacts: [XcircuiteFileReference],
        evidenceArtifacts: [XcircuiteFileReference],
        toolEvidence: [ToolEvidence],
        policy: ReleaseQualificationPolicy,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.projectRoot = projectRoot
        self.processProfileID = processProfileID
        self.suiteArtifact = suiteArtifact
        self.qualificationReportArtifact = qualificationReportArtifact
        self.domainReportArtifacts = domainReportArtifacts
        self.evidenceArtifacts = evidenceArtifacts
        self.toolEvidence = toolEvidence
        self.policy = policy
        self.inputs = Array(Set(
            [suiteArtifact, qualificationReportArtifact]
                + domainReportArtifacts
                + evidenceArtifacts
        )).sorted { $0.path < $1.path }
    }
}
