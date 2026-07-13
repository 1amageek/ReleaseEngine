import Foundation
import ReleaseCore
import CircuiteFoundation

public struct SignoffEvidenceValidationResult: Sendable, Hashable, Codable {
    public var verifiedEvidenceIDs: [String]
    public var blockedEvidenceIDs: [String]
    public var blockedAxes: [ReleaseSignoffAxis]
    public var diagnosticCodesByAxis: [ReleaseSignoffAxis: [String]]
    public var diagnostics: [DesignDiagnostic]

    public init(
        verifiedEvidenceIDs: [String] = [],
        blockedEvidenceIDs: [String] = [],
        blockedAxes: [ReleaseSignoffAxis] = [],
        diagnosticCodesByAxis: [ReleaseSignoffAxis: [String]] = [:],
        diagnostics: [DesignDiagnostic] = []
    ) {
        self.verifiedEvidenceIDs = verifiedEvidenceIDs
        self.blockedEvidenceIDs = blockedEvidenceIDs
        self.blockedAxes = blockedAxes
        self.diagnosticCodesByAxis = diagnosticCodesByAxis
        self.diagnostics = diagnostics
    }
}
