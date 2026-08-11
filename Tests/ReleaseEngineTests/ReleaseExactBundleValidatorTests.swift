import CircuiteFoundation
import DesignDatabaseCore
import Foundation
import ReleaseCore
import Testing

@Suite("Exact release bundle validation")
struct ReleaseExactBundleValidatorTests {
    @Test("exact revision, content, and active retention inventory passes")
    func acceptsCompleteLineage() throws {
        let fixture = try Fixture()

        try DefaultReleaseExactBundleValidator().validate(fixture.bundle)
    }

    @Test("a database revision without an active retention receipt fails")
    func rejectsMissingRetention() throws {
        let fixture = try Fixture()
        let invalid = ReleaseExactBundle(
            databaseRevisions: fixture.bundle.databaseRevisions,
            semanticDependencyGraphDigest: fixture.bundle.semanticDependencyGraphDigest,
            contentIdentities: fixture.bundle.contentIdentities,
            approvalContentIdentities: fixture.bundle.approvalContentIdentities,
            qualificationContentIdentities: fixture.bundle.qualificationContentIdentities,
            retentionReceipts: []
        )

        #expect(throws: ReleaseExactBundleValidationError.retentionInventoryMismatch) {
            try DefaultReleaseExactBundleValidator().validate(invalid)
        }
    }

    @Test("released retention cannot authorize a release")
    func rejectsReleasedRetention() throws {
        let fixture = try Fixture()
        let receipt = try #require(fixture.bundle.retentionReceipts.first)
        let released = DesignRevisionRetentionReceipt(
            operation: receipt.operation,
            claimID: receipt.claimID,
            revision: receipt.revision,
            generation: receipt.generation + 1,
            reachabilityGeneration: receipt.reachabilityGeneration,
            state: .released,
            outcomeDigest: receipt.outcomeDigest
        )
        let invalid = ReleaseExactBundle(
            databaseRevisions: fixture.bundle.databaseRevisions,
            semanticDependencyGraphDigest: fixture.bundle.semanticDependencyGraphDigest,
            contentIdentities: fixture.bundle.contentIdentities,
            approvalContentIdentities: fixture.bundle.approvalContentIdentities,
            qualificationContentIdentities: fixture.bundle.qualificationContentIdentities,
            retentionReceipts: [released]
        )

        #expect(throws: ReleaseExactBundleValidationError.inactiveRetentionReceipt(
            receipt.revision
        )) {
            try DefaultReleaseExactBundleValidator().validate(invalid)
        }
    }

    @Test("decoding rejects an unsupported exact bundle schema")
    func decoderRejectsUnsupportedSchema() throws {
        let fixture = try Fixture()
        let encoded = try JSONEncoder().encode(fixture.bundle)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = ReleaseExactBundle.currentSchemaVersion + 1
        let invalid = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: ReleaseExactBundleValidationError.unsupportedSchemaVersion(
            actual: ReleaseExactBundle.currentSchemaVersion + 1,
            expected: ReleaseExactBundle.currentSchemaVersion
        )) {
            _ = try JSONDecoder().decode(ReleaseExactBundle.self, from: invalid)
        }
    }

    @Test("decoding rejects duplicate content identities")
    func decoderRejectsDuplicateContentIdentity() throws {
        let fixture = try Fixture()
        let duplicate = try #require(fixture.bundle.contentIdentities.first)
        let invalid = ReleaseExactBundle(
            databaseRevisions: fixture.bundle.databaseRevisions,
            semanticDependencyGraphDigest: fixture.bundle.semanticDependencyGraphDigest,
            contentIdentities: fixture.bundle.contentIdentities + [duplicate],
            approvalContentIdentities: fixture.bundle.approvalContentIdentities,
            qualificationContentIdentities: fixture.bundle.qualificationContentIdentities,
            retentionReceipts: fixture.bundle.retentionReceipts
        )

        #expect(throws: ReleaseExactBundleValidationError.duplicateContentIdentity(
            duplicate
        )) {
            _ = try JSONDecoder().decode(
                ReleaseExactBundle.self,
                from: JSONEncoder().encode(invalid)
            )
        }
    }

    @Test("zero retention generations cannot authorize a release")
    func rejectsZeroRetentionGeneration() throws {
        let fixture = try Fixture()
        let receipt = try #require(fixture.bundle.retentionReceipts.first)
        let invalidReceipt = DesignRevisionRetentionReceipt(
            operation: receipt.operation,
            claimID: receipt.claimID,
            revision: receipt.revision,
            generation: 0,
            reachabilityGeneration: receipt.reachabilityGeneration,
            state: receipt.state,
            outcomeDigest: receipt.outcomeDigest
        )
        let invalid = ReleaseExactBundle(
            databaseRevisions: fixture.bundle.databaseRevisions,
            semanticDependencyGraphDigest: fixture.bundle.semanticDependencyGraphDigest,
            contentIdentities: fixture.bundle.contentIdentities,
            approvalContentIdentities: fixture.bundle.approvalContentIdentities,
            qualificationContentIdentities: fixture.bundle.qualificationContentIdentities,
            retentionReceipts: [invalidReceipt]
        )

        #expect(throws: ReleaseExactBundleValidationError.invalidRetentionGeneration(
            receipt.revision
        )) {
            try DefaultReleaseExactBundleValidator().validate(invalid)
        }
    }

    private struct Fixture {
        let bundle: ReleaseExactBundle

        init() throws {
            let databaseID = try DesignDatabaseID(high: 1, low: 1)
            let revision = DesignRevisionReference(
                databaseID: databaseID,
                revisionID: DesignRevisionID(high: 2, low: 2)
            )
            let content = try ArtifactID(
                digest: ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "a", count: 64)
                ),
                byteCount: 64
            )
            let approval = try ArtifactID(
                digest: ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "b", count: 64)
                ),
                byteCount: 32
            )
            let qualification = try ArtifactID(
                digest: ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "c", count: 64)
                ),
                byteCount: 48
            )
            let receipt = DesignRevisionRetentionReceipt(
                operation: DesignDatabaseOperationReference(
                    databaseID: databaseID,
                    authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
                        high: 3,
                        low: 3
                    ),
                    operationID: try DesignDatabaseOperationID(
                        rawValue: "release-retention"
                    )
                ),
                claimID: try DesignRevisionRetentionID(rawValue: "release"),
                revision: revision,
                generation: 1,
                reachabilityGeneration: 1,
                state: .active,
                outcomeDigest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "d", count: 64)
                )
            )
            bundle = ReleaseExactBundle(
                databaseRevisions: [
                    ReleaseDatabaseRevisionBinding(
                        databaseRole: "design",
                        revision: revision
                    )
                ],
                semanticDependencyGraphDigest: try ContentDigest(
                    algorithm: .sha256,
                    hexadecimalValue: String(repeating: "e", count: 64)
                ),
                contentIdentities: [content, approval, qualification],
                approvalContentIdentities: [approval],
                qualificationContentIdentities: [qualification],
                retentionReceipts: [receipt]
            )
        }
    }
}
