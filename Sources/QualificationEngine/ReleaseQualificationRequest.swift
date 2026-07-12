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
    public var corpusSpecArtifacts: [XcircuiteFileReference]
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
        corpusSpecArtifacts: [XcircuiteFileReference] = [],
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
        self.corpusSpecArtifacts = corpusSpecArtifacts
        self.domainReportArtifacts = domainReportArtifacts
        self.evidenceArtifacts = evidenceArtifacts
        self.toolEvidence = toolEvidence
        self.policy = policy
        self.inputs = Array(Set(
            [suiteArtifact, qualificationReportArtifact]
                + corpusSpecArtifacts
                + domainReportArtifacts
                + evidenceArtifacts
        )).sorted { $0.path < $1.path }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case inputs
        case projectRoot
        case processProfileID
        case suiteArtifact
        case qualificationReportArtifact
        case corpusSpecArtifacts
        case domainReportArtifacts
        case evidenceArtifacts
        case toolEvidence
        case policy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        inputs = try container.decodeIfPresent([XcircuiteFileReference].self, forKey: .inputs) ?? []
        projectRoot = try container.decodeIfPresent(String.self, forKey: .projectRoot)
        processProfileID = try container.decode(String.self, forKey: .processProfileID)
        suiteArtifact = try container.decode(XcircuiteFileReference.self, forKey: .suiteArtifact)
        qualificationReportArtifact = try container.decode(XcircuiteFileReference.self, forKey: .qualificationReportArtifact)
        corpusSpecArtifacts = try container.decodeIfPresent([XcircuiteFileReference].self, forKey: .corpusSpecArtifacts) ?? []
        domainReportArtifacts = try container.decodeIfPresent([XcircuiteFileReference].self, forKey: .domainReportArtifacts) ?? []
        evidenceArtifacts = try container.decodeIfPresent([XcircuiteFileReference].self, forKey: .evidenceArtifacts) ?? []
        toolEvidence = try container.decodeIfPresent([ToolEvidence].self, forKey: .toolEvidence) ?? []
        policy = try container.decode(ReleaseQualificationPolicy.self, forKey: .policy)
    }
}
