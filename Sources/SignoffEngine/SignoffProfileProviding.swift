import Foundation
import ReleaseCore

public protocol SignoffProfileProviding: Sendable {
    func profile(profileID: String) -> ReleaseSignoffProfile?
}
