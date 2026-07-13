import Foundation

public enum ReleaseProfileRequiredPromotionStatus: String, Sendable, Hashable, Codable, Comparable {
    case corpusChecked
    case oracleChecked
    case productionEligible

    public static func < (
        lhs: ReleaseProfileRequiredPromotionStatus,
        rhs: ReleaseProfileRequiredPromotionStatus
    ) -> Bool {
        lhs.rank < rhs.rank
    }

    public var rank: Int {
        switch self {
        case .corpusChecked:
            1
        case .oracleChecked:
            2
        case .productionEligible:
            3
        }
    }
}
