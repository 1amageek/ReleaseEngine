import Foundation

public struct ReleaseQualificationLane: Sendable, Hashable, Codable {
    public var laneID: String
    public var domain: String
    public var kind: ReleaseQualificationLaneKind
    public var corpusSpecPath: String?
    public var reportPath: String?
    public var evidenceExportPath: String?
    public var oracleBackendID: String?
    public var requiredProbeIDs: [String]

    public init(
        laneID: String,
        domain: String,
        kind: ReleaseQualificationLaneKind,
        corpusSpecPath: String? = nil,
        reportPath: String? = nil,
        evidenceExportPath: String? = nil,
        oracleBackendID: String? = nil,
        requiredProbeIDs: [String] = []
    ) {
        self.laneID = laneID
        self.domain = domain
        self.kind = kind
        self.corpusSpecPath = corpusSpecPath
        self.reportPath = reportPath
        self.evidenceExportPath = evidenceExportPath
        self.oracleBackendID = oracleBackendID
        self.requiredProbeIDs = requiredProbeIDs
    }

    public var isValid: Bool {
        !laneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Set(requiredProbeIDs).count == requiredProbeIDs.count
            && (kind == .nativeCorpus || !(oracleBackendID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private enum CodingKeys: String, CodingKey {
        case laneID
        case domain
        case kind
        case corpusSpec
        case corpusSpecPath
        case reportPath
        case evidenceExportPath
        case oracleBackendID
        case requiredProbeIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        laneID = try container.decode(String.self, forKey: .laneID)
        domain = try container.decode(String.self, forKey: .domain)
        kind = try container.decode(ReleaseQualificationLaneKind.self, forKey: .kind)
        let explicitCorpusSpecPath = try container.decodeIfPresent(String.self, forKey: .corpusSpecPath)
        let legacyCorpusSpecPath = try container.decodeIfPresent(String.self, forKey: .corpusSpec)
        corpusSpecPath = explicitCorpusSpecPath ?? legacyCorpusSpecPath
        reportPath = try container.decodeIfPresent(String.self, forKey: .reportPath)
        evidenceExportPath = try container.decodeIfPresent(String.self, forKey: .evidenceExportPath)
        oracleBackendID = try container.decodeIfPresent(String.self, forKey: .oracleBackendID)
        requiredProbeIDs = try container.decodeIfPresent([String].self, forKey: .requiredProbeIDs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(laneID, forKey: .laneID)
        try container.encode(domain, forKey: .domain)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(corpusSpecPath, forKey: .corpusSpec)
        try container.encodeIfPresent(reportPath, forKey: .reportPath)
        try container.encodeIfPresent(evidenceExportPath, forKey: .evidenceExportPath)
        try container.encodeIfPresent(oracleBackendID, forKey: .oracleBackendID)
        try container.encode(requiredProbeIDs, forKey: .requiredProbeIDs)
    }
}
