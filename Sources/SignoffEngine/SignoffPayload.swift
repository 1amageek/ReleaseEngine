import Foundation
import XcircuitePackage
import ReleaseCore

public struct SignoffPayload: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var approved: Bool
    public var blockedAxes: [String]
    public var bundle: SignoffBundleReference?
    public var profileID: String
    public var designDigest: String?
    public var pdkDigest: String?
    public var axisResults: [SignoffAxisResult]
    public var waivers: [SignoffWaiver]

    public init(
        approved: Bool,
        blockedAxes: [String],
        bundle: SignoffBundleReference?,
        profileID: String = "",
        designDigest: String? = nil,
        pdkDigest: String? = nil,
        axisResults: [SignoffAxisResult] = [],
        waivers: [SignoffWaiver] = [],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.approved = approved
        self.blockedAxes = blockedAxes
        self.bundle = bundle
        self.profileID = profileID
        self.designDigest = designDigest
        self.pdkDigest = pdkDigest
        self.axisResults = axisResults
        self.waivers = waivers
    }
}
