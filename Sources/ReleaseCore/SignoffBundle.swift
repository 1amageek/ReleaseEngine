import Foundation
import LogicIR
import CircuiteFoundation
import ToolQualification

public struct SignoffBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 5

    public var schemaVersion: Int
    public var bundleID: String
    public var profileID: String
    public var designDigest: String
    public var designProvenance: LogicDesignProvenance?
    public var pdkDigest: String
    public var finalLayoutDigest: String
    public var axisResults: [SignoffAxisResult]
    public var waivers: [SignoffWaiver]
    public var evidenceRecords: [ReleaseSignoffEvidenceReference]
    public var evidenceArtifacts: [ArtifactReference]
    public var toolQualificationScopes: [ToolQualificationScope]
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
        evidenceRecords: [ReleaseSignoffEvidenceReference] = [],
        evidenceArtifacts: [ArtifactReference],
        toolQualificationScopes: [ToolQualificationScope] = [],
        evidenceDigest: String,
        issuedAt: Date,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.bundleID = bundleID
        self.profileID = profileID
        self.designDigest = designDigest.lowercased()
        self.designProvenance = designProvenance
        self.pdkDigest = pdkDigest.lowercased()
        self.finalLayoutDigest = finalLayoutDigest.lowercased()
        self.axisResults = axisResults.map {
            SignoffAxisResult(
                axis: $0.axis,
                disposition: $0.disposition,
                evidenceIDs: $0.evidenceIDs,
                diagnosticCodes: $0.diagnosticCodes,
                reason: $0.reason,
                waiverID: $0.waiverID
            )
        }.sorted { $0.axis < $1.axis }
        self.waivers = waivers.map {
            SignoffWaiver(
                waiverID: $0.waiverID,
                axis: $0.axis,
                reason: $0.reason,
                authority: $0.authority,
                approvedAt: $0.approvedAt,
                expiresAt: $0.expiresAt,
                affectedEvidenceIDs: $0.affectedEvidenceIDs,
                designDigest: $0.designDigest,
                pdkDigest: $0.pdkDigest,
                toolID: $0.toolID,
                toolDigest: $0.toolDigest
            )
        }.sorted { $0.waiverID < $1.waiverID }
        self.evidenceRecords = evidenceRecords.sorted { $0.evidenceID < $1.evidenceID }
        self.evidenceArtifacts = Array(Set(evidenceArtifacts)).sorted(by: Self.artifactSort)
        self.toolQualificationScopes = toolQualificationScopes.sorted(by: Self.scopeSort)
        self.evidenceDigest = evidenceDigest.lowercased()
        self.issuedAt = Date(
            timeIntervalSince1970: issuedAt.timeIntervalSince1970.rounded(.down)
        )
    }

    private static func scopeSort(
        _ lhs: ToolQualificationScope,
        _ rhs: ToolQualificationScope
    ) -> Bool {
        let lhsKey = [
            lhs.implementationID,
            lhs.toolVersion,
            lhs.binaryDigest,
            lhs.algorithmVersion,
            lhs.processProfileID,
            lhs.processProfileDigest,
            lhs.deckDigest,
            lhs.pdkID ?? "",
            lhs.pdkDigest ?? "",
            lhs.oracle?.implementationID ?? "",
            lhs.oracle?.version ?? "",
            lhs.oracle?.binaryDigest ?? "",
        ]
        let rhsKey = [
            rhs.implementationID,
            rhs.toolVersion,
            rhs.binaryDigest,
            rhs.algorithmVersion,
            rhs.processProfileID,
            rhs.processProfileDigest,
            rhs.deckDigest,
            rhs.pdkID ?? "",
            rhs.pdkDigest ?? "",
            rhs.oracle?.implementationID ?? "",
            rhs.oracle?.version ?? "",
            rhs.oracle?.binaryDigest ?? "",
        ]
        return lhsKey.lexicographicallyPrecedes(rhsKey)
    }

    private static func artifactSort(
        _ lhs: ArtifactReference,
        _ rhs: ArtifactReference
    ) -> Bool {
        let lhsKey = [
            lhs.id.description,
            lhs.descriptor.role.rawValue,
            lhs.descriptor.kind.rawValue,
            lhs.descriptor.format.rawValue,
            lhs.digest.algorithm.rawValue,
            lhs.digest.hexadecimalValue,
            String(lhs.byteCount),
        ]
        let rhsKey = [
            rhs.id.description,
            rhs.descriptor.role.rawValue,
            rhs.descriptor.kind.rawValue,
            rhs.descriptor.format.rawValue,
            rhs.digest.algorithm.rawValue,
            rhs.digest.hexadecimalValue,
            String(rhs.byteCount),
        ]
        return lhsKey.lexicographicallyPrecedes(rhsKey)
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
        guard bundle.schemaVersion == currentSchemaVersion else {
            throw SignoffBundleCanonicalEncodingError.unsupportedSchemaVersion(bundle.schemaVersion)
        }
        let normalized = SignoffBundle(
            bundleID: bundle.bundleID,
            profileID: bundle.profileID,
            designDigest: bundle.designDigest,
            designProvenance: bundle.designProvenance,
            pdkDigest: bundle.pdkDigest,
            finalLayoutDigest: bundle.finalLayoutDigest,
            axisResults: bundle.axisResults,
            waivers: bundle.waivers,
            evidenceRecords: bundle.evidenceRecords,
            evidenceArtifacts: bundle.evidenceArtifacts,
            toolQualificationScopes: bundle.toolQualificationScopes,
            evidenceDigest: bundle.evidenceDigest,
            issuedAt: bundle.issuedAt,
            schemaVersion: bundle.schemaVersion
        )
        guard normalized == bundle else {
            throw SignoffBundleCanonicalEncodingError.decodedBundleIsNotCanonical
        }
        guard normalized.isReleaseReady else {
            throw SignoffBundleCanonicalEncodingError.invalidReleaseContent
        }
        guard try normalized.canonicalData() == data else {
            throw SignoffBundleCanonicalEncodingError.decodedBundleIsNotCanonical
        }
        return normalized
    }

    public var isReleaseReady: Bool {
        let axes = axisResults.map(\.axis)
        let waiverIDs = waivers.map(\.waiverID)
        let waiverAxes = waivers.map(\.axis)
        let scopes = Set(toolQualificationScopes)
        let artifacts = Set(evidenceArtifacts)
        let resultEvidenceIDs = axisResults.flatMap(\.evidenceIDs)
        let recordEvidenceIDs = evidenceRecords.map(\.evidenceID)
        let recordArtifacts = Set(evidenceRecords.map(\.artifact))
        return Self.isToken(bundleID)
            && Self.isToken(profileID)
            && Self.isSHA256(designDigest)
            && Self.isSHA256(pdkDigest)
            && Self.isSHA256(finalLayoutDigest)
            && Self.isSHA256(evidenceDigest)
            && axes.count == ReleaseSignoffAxis.allCases.count
            && Set(axes) == Set(ReleaseSignoffAxis.allCases)
            && axisResults.allSatisfy { $0.disposition.isReleaseEligible }
            && axisResults.allSatisfy {
                ($0.disposition == .profileApprovedNotApplicable || !$0.evidenceIDs.isEmpty)
                    && $0.evidenceIDs.count == Set($0.evidenceIDs).count
                    && $0.evidenceIDs.allSatisfy(Self.isToken)
            }
            && resultEvidenceIDs.count == Set(resultEvidenceIDs).count
            && recordEvidenceIDs.count == Set(recordEvidenceIDs).count
            && (evidenceRecords.isEmpty || axisResults.allSatisfy { result in
                Set(result.evidenceIDs) == Set(
                    evidenceRecords.filter { $0.axis == result.axis }.map(\.evidenceID)
                )
            })
            && waiversAreValid(at: issuedAt)
            && waiverIDs.count == Set(waiverIDs).count
            && waiverAxes.count == Set(waiverAxes).count
            && !evidenceArtifacts.isEmpty
            && evidenceArtifacts.count == artifacts.count
            && (evidenceRecords.isEmpty || recordArtifacts == artifacts)
            && evidenceArtifacts.allSatisfy {
                $0.digest.algorithm == .sha256
                    && $0.byteCount > 0
            }
            && evidenceRecords.allSatisfy {
                $0.executionProvenance.producer.kind == .tool
                    && $0.executionProvenance.producer.identifier == $0.toolID
                    && $0.executionProvenance.producer.version == $0.toolVersion
            }
            && !toolQualificationScopes.isEmpty
            && toolQualificationScopes.count == scopes.count
            && toolQualificationScopes.allSatisfy {
                $0.isCompleteForProduction
                    && $0.pdkDigest?.caseInsensitiveCompare(pdkDigest) == .orderedSame
            }
            && issuedAt.timeIntervalSinceReferenceDate.isFinite
    }

    public func waiversAreValid(at evaluatedAt: Date) -> Bool {
        guard evaluatedAt.timeIntervalSinceReferenceDate.isFinite,
              issuedAt.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }
        let waivedResults = axisResults.filter { $0.disposition == .waived }
        let waiversByID = Dictionary(grouping: waivers, by: \.waiverID)
        guard waivedResults.count == waivers.count,
              waivedResults.allSatisfy({ result in
                  guard let waiverID = result.waiverID,
                        let matches = waiversByID[waiverID],
                        matches.count == 1,
                        let waiver = matches.first else {
                      return false
                  }
                  return waiver.axis == result.axis
                      && Set(waiver.affectedEvidenceIDs).isSubset(of: Set(result.evidenceIDs))
              }) else {
            return false
        }
        return waivers.allSatisfy { waiver in
            Self.isToken(waiver.waiverID)
                && !waiver.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Self.isToken(waiver.authority)
                && !waiver.affectedEvidenceIDs.isEmpty
                && waiver.affectedEvidenceIDs.count == Set(waiver.affectedEvidenceIDs).count
                && waiver.approvedAt <= issuedAt
                && waiver.approvedAt < waiver.expiresAt
                && evaluatedAt < waiver.expiresAt
                && waiver.designDigest == designDigest
                && waiver.pdkDigest == pdkDigest
                && ((waiver.toolID == nil && waiver.toolDigest == nil)
                    || (waiver.toolID.map(Self.isToken) == true
                        && waiver.toolDigest.map(Self.isSHA256) == true))
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }

    private static func isToken(_ value: String) -> Bool {
        !value.isEmpty
            && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
            && !value.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }
}
