import Foundation

public enum ReleaseSignoffAxis: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case simulation
    case logicSynthesisEquivalence
    case rtlLint
    case clockDomainCrossing
    case resetDomainCrossing
    case formalProof
    case scanInsertion
    case automaticTestPatternGeneration
    case builtInSelfTest
    case powerIntent
    case timing
    case crosstalkNoise
    case electromigration
    case irDrop
    case drc
    case lvs
    case pex
    case antenna
    case density
    case metalFill
    case erc
    case esd
    case latchUp
    case aging
    case designForManufacturability

    public static func < (lhs: ReleaseSignoffAxis, rhs: ReleaseSignoffAxis) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
