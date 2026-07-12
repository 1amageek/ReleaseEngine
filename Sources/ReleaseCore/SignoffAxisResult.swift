import Foundation

public struct SignoffAxisResult: Sendable, Hashable, Codable {
    public var axis: ReleaseSignoffAxis
    public var disposition: ReleaseAxisDisposition
    public var evidenceIDs: [String]
    public var diagnosticCodes: [String]
    public var reason: String
    public var waiverID: String?

    public init(
        axis: ReleaseSignoffAxis,
        disposition: ReleaseAxisDisposition,
        evidenceIDs: [String] = [],
        diagnosticCodes: [String] = [],
        reason: String,
        waiverID: String? = nil
    ) {
        self.axis = axis
        self.disposition = disposition
        self.evidenceIDs = evidenceIDs
        self.diagnosticCodes = diagnosticCodes
        self.reason = reason
        self.waiverID = waiverID
    }
}
