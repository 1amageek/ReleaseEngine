import Foundation

public enum ReleaseQualificationPromotionStatus: String, Sendable, Hashable, Codable {
    case blocked
    case corpusChecked
    case oracleChecked
    case productionEligible
}
