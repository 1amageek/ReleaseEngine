import Foundation

public struct SignoffWaiver: Sendable, Hashable, Codable {
    public var waiverID: String
    public var axis: ReleaseSignoffAxis
    public var reason: String
    public var authority: String
    public var approvedAt: Date
    public var expiresAt: Date
    public var affectedEvidenceIDs: [String]
    public var designDigest: String
    public var pdkDigest: String
    public var toolID: String?
    public var toolDigest: String?

    public init(
        waiverID: String,
        axis: ReleaseSignoffAxis,
        reason: String,
        authority: String,
        approvedAt: Date,
        expiresAt: Date,
        affectedEvidenceIDs: [String],
        designDigest: String,
        pdkDigest: String,
        toolID: String? = nil,
        toolDigest: String? = nil
    ) {
        self.waiverID = waiverID
        self.axis = axis
        self.reason = reason
        self.authority = authority
        self.approvedAt = approvedAt
        self.expiresAt = expiresAt
        self.affectedEvidenceIDs = affectedEvidenceIDs
        self.designDigest = designDigest
        self.pdkDigest = pdkDigest
        self.toolID = toolID
        self.toolDigest = toolDigest
    }
}
