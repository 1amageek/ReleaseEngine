import Foundation

public struct RetainedCorpusCaseResult: Sendable, Hashable, Codable {
    public var caseID: String
    public var domain: String
    public var status: String?
    public var qualified: Bool
    public var coverageTags: [String]
    public var probeIDs: [String]

    public init(
        caseID: String,
        domain: String,
        status: String?,
        qualified: Bool,
        coverageTags: [String] = [],
        probeIDs: [String] = []
    ) {
        self.caseID = caseID
        self.domain = domain
        self.status = status
        self.qualified = qualified
        self.coverageTags = coverageTags
        self.probeIDs = probeIDs
    }

    public var isValid: Bool {
        !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && coverageTags.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && probeIDs.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && Set(coverageTags).count == coverageTags.count
            && Set(probeIDs).count == probeIDs.count
    }
}
