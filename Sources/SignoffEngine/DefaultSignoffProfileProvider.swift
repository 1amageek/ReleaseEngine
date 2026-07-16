import Foundation
import ReleaseCore
import ToolQualification
import CircuiteFoundation

public struct DefaultSignoffProfileProvider: SignoffProfileProviding {
    public init() {}

    public func profile(profileID: String) -> ReleaseSignoffProfile? {
        switch profileID {
        case "digital":
            Self.digitalProfile
        case "analog":
            Self.analogProfile
        case "mixed-signal", "mixedSignal":
            Self.mixedSignalProfile
        default:
            nil
        }
    }

    public static let digitalProfile = ReleaseSignoffProfile(
        profileID: "digital",
        designKind: .digital,
        requirements: productionRequirements
    )

    public static let analogProfile = ReleaseSignoffProfile(
        profileID: "analog",
        designKind: .analog,
        requirements: productionRequirements
    )

    public static let mixedSignalProfile = ReleaseSignoffProfile(
        profileID: "mixed-signal",
        designKind: .mixedSignal,
        requirements: productionRequirements
    )

    private static var productionRequirements: [ReleaseSignoffAxisRequirement] {
        ReleaseSignoffAxis.allCases.map {
            requirement($0, required: true, level: .productionEligible)
        }
    }

    private static func requirement(
        _ axis: ReleaseSignoffAxis,
        required: Bool,
        level: ToolQualificationLevel = .smokeChecked
    ) -> ReleaseSignoffAxisRequirement {
        ReleaseSignoffAxisRequirement(
            axis: axis,
            required: required,
            minimumEvidenceCount: required ? 1 : 0,
            minimumQualificationLevel: level,
            requiredArtifactKinds: required ? [.report] : []
        )
    }
}
