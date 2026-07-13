import Foundation
import CryptoKit
import LogicIR
import CircuiteFoundation

public struct SignoffBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

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
    public var approvalDigest: String

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
        approvalDigest: String,
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
        self.approvalDigest = approvalDigest
    }

    public func computedApprovalDigest() -> String {
        let axisMaterial = axisResults
            .sorted { $0.axis.rawValue < $1.axis.rawValue }
            .map {
                [
                    $0.axis.rawValue,
                    $0.disposition.rawValue,
                    $0.evidenceIDs.sorted().joined(separator: ","),
                    $0.diagnosticCodes.sorted().joined(separator: ","),
                    $0.reason,
                    $0.waiverID ?? "",
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
        let waiverMaterial = waivers
            .sorted { $0.waiverID < $1.waiverID }
            .map {
                [
                    $0.waiverID,
                    $0.axis.rawValue,
                    $0.reason,
                    $0.authority,
                    $0.approvedAt.iso8601String,
                    $0.expiresAt.iso8601String,
                    $0.affectedEvidenceIDs.sorted().joined(separator: ","),
                    $0.designDigest,
                    $0.pdkDigest,
                    $0.toolID ?? "",
                    $0.toolDigest ?? "",
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
        let material = [
            String(schemaVersion),
            bundleID,
            profileID,
            designDigest,
            designProvenance?.canonicalMaterial ?? "",
            pdkDigest,
            finalLayoutDigest,
            evidenceDigest,
            issuedAt.iso8601String,
            axisMaterial,
            waiverMaterial,
        ].joined(separator: "\n")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public var isSelfConsistent: Bool {
        approvalDigest == computedApprovalDigest()
    }
}

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
