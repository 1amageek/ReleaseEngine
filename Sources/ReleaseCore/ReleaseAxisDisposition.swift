import Foundation

public enum ReleaseAxisDisposition: String, Sendable, Hashable, Codable {
    case passed
    case failed
    case blocked
    case profileApprovedNotApplicable
    case waived

    public var isReleaseEligible: Bool {
        switch self {
        case .passed, .profileApprovedNotApplicable, .waived:
            true
        case .failed, .blocked:
            false
        }
    }
}
