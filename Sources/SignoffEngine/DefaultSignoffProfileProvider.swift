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
        requirements: [
            requirement(.simulation, required: true, level: .smokeChecked),
            requirement(.timing, required: true, level: .corpusChecked),
            requirement(.powerIntegrity, required: true, level: .corpusChecked),
            requirement(.drc, required: true, level: .corpusChecked),
            requirement(.lvs, required: true, level: .corpusChecked),
            requirement(.pex, required: true, level: .corpusChecked),
            requirement(.erc, required: false),
            requirement(.esd, required: false),
            requirement(.latchUp, required: false),
            requirement(.aging, required: false),
        ]
    )

    public static let analogProfile = ReleaseSignoffProfile(
        profileID: "analog",
        designKind: .analog,
        requirements: [
            requirement(.simulation, required: true, level: .corpusChecked),
            requirement(.timing, required: false),
            requirement(.powerIntegrity, required: true, level: .corpusChecked),
            requirement(.drc, required: true, level: .corpusChecked),
            requirement(.lvs, required: true, level: .corpusChecked),
            requirement(.pex, required: true, level: .corpusChecked),
            requirement(.erc, required: true, level: .corpusChecked),
            requirement(.esd, required: true, level: .corpusChecked),
            requirement(.latchUp, required: true, level: .corpusChecked),
            requirement(.aging, required: true, level: .corpusChecked),
        ]
    )

    public static let mixedSignalProfile = ReleaseSignoffProfile(
        profileID: "mixed-signal",
        designKind: .mixedSignal,
        requirements: ReleaseSignoffAxis.allCases.map {
            requirement($0, required: true, level: $0 == .simulation ? .smokeChecked : .corpusChecked)
        }
    )

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
