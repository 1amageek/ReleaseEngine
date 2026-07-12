import Foundation

public struct RetainedOracleCaseResult: Sendable, Hashable, Codable {
    public var caseID: String
    public var domain: String
    public var nativeStatus: String?
    public var oracleStatus: String?
    public var agreement: Bool?
    public var coverageTags: [String]
    public var probeIDs: [String]

    public init(
        caseID: String,
        domain: String,
        nativeStatus: String?,
        oracleStatus: String?,
        agreement: Bool?,
        coverageTags: [String] = [],
        probeIDs: [String] = []
    ) {
        self.caseID = caseID
        self.domain = domain
        self.nativeStatus = nativeStatus
        self.oracleStatus = oracleStatus
        self.agreement = agreement
        self.coverageTags = coverageTags
        self.probeIDs = probeIDs
    }

    public var isValid: Bool {
        !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && nativeStatus.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
            && oracleStatus.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
            && agreement != nil
            && coverageTags.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && probeIDs.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && Set(coverageTags).count == coverageTags.count
            && Set(probeIDs).count == probeIDs.count
    }
}
