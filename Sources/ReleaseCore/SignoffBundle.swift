import Foundation
import LogicIR
import CircuiteFoundation

public struct SignoffBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var bundleID: String
    public var profileID: String
    public var designDigest: String
    public var designProvenance: LogicDesignProvenance?
    public var pdkDigest: String
    public var finalLayoutDigest: String
    public var axisResults: [SignoffAxisResult]
    public var waivers: [SignoffWaiver]
    public var evidenceDigest: String
    public var issuedAt: Date

    public init(
        bundleID: String,
        profileID: String,
        designDigest: String,
        designProvenance: LogicDesignProvenance? = nil,
        pdkDigest: String,
        finalLayoutDigest: String,
        axisResults: [SignoffAxisResult],
        waivers: [SignoffWaiver],
        evidenceDigest: String,
        issuedAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.bundleID = bundleID
        self.profileID = profileID
        self.designDigest = designDigest
        self.designProvenance = designProvenance
        self.pdkDigest = pdkDigest
        self.finalLayoutDigest = finalLayoutDigest
        self.axisResults = axisResults
        self.waivers = waivers
        self.evidenceDigest = evidenceDigest
        self.issuedAt = issuedAt
    }

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decodeCanonical(from data: Data) throws -> SignoffBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(SignoffBundle.self, from: data)
        guard try bundle.canonicalData() == data else {
            throw SignoffBundleCanonicalEncodingError.decodedBundleIsNotCanonical
        }
        return bundle
    }
}
