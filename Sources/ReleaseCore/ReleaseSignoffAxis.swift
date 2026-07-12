import Foundation

public enum ReleaseSignoffAxis: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case simulation
    case timing
    case powerIntegrity
    case drc
    case lvs
    case pex
    case erc
    case esd
    case latchUp
    case aging

    public static func < (lhs: ReleaseSignoffAxis, rhs: ReleaseSignoffAxis) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
