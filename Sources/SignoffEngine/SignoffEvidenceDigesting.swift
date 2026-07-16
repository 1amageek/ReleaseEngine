import Foundation
import ReleaseCore

public protocol SignoffEvidenceDigesting: Sendable {
    func digest(_ evidence: [ReleaseSignoffEvidenceReference]) throws -> String
}
