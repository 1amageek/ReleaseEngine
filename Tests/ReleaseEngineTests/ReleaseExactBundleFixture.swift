import CircuiteFoundation
import DesignDatabaseCore
import ReleaseCore

func makeTestReleaseExactBundle(
    contentArtifacts: [ArtifactReference],
    approvalArtifacts: [ArtifactReference],
    qualificationArtifacts: [ArtifactReference]
) throws -> ReleaseExactBundle {
    let databaseID = try DesignDatabaseID(high: 0, low: 1)
    let revision = DesignRevisionReference(
        databaseID: databaseID,
        revisionID: DesignRevisionID(high: 0, low: 1)
    )
    let operation = DesignDatabaseOperationReference(
        databaseID: databaseID,
        authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
            high: 0,
            low: 1
        ),
        operationID: try DesignDatabaseOperationID(
            rawValue: "release-fixture-retention"
        )
    )
    let retention = DesignRevisionRetentionReceipt(
        operation: operation,
        claimID: try DesignRevisionRetentionID(rawValue: "release-fixture"),
        revision: revision,
        generation: 1,
        reachabilityGeneration: 1,
        state: .active,
        outcomeDigest: try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "e", count: 64)
        )
    )
    return ReleaseExactBundle(
        databaseRevisions: [
            ReleaseDatabaseRevisionBinding(
                databaseRole: "design",
                revision: revision
            )
        ],
        semanticDependencyGraphDigest: try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: String(repeating: "d", count: 64)
        ),
        contentIdentities: Array(Set(contentArtifacts.map(\.id))),
        approvalContentIdentities: Array(Set(approvalArtifacts.map(\.id))),
        qualificationContentIdentities: Array(Set(qualificationArtifacts.map(\.id))),
        retentionReceipts: [retention]
    )
}
