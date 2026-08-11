import CircuiteFoundation
import DesignDatabaseCore

public struct ReleaseExactBundle: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let databaseRevisions: [ReleaseDatabaseRevisionBinding]
    public let semanticDependencyGraphDigest: ContentDigest
    public let contentIdentities: [ArtifactID]
    public let approvalContentIdentities: [ArtifactID]
    public let qualificationContentIdentities: [ArtifactID]
    public let retentionReceipts: [DesignRevisionRetentionReceipt]

    public init(
        databaseRevisions: [ReleaseDatabaseRevisionBinding],
        semanticDependencyGraphDigest: ContentDigest,
        contentIdentities: [ArtifactID],
        approvalContentIdentities: [ArtifactID],
        qualificationContentIdentities: [ArtifactID],
        retentionReceipts: [DesignRevisionRetentionReceipt]
    ) {
        self.init(
            schemaVersion: Self.currentSchemaVersion,
            databaseRevisions: databaseRevisions,
            semanticDependencyGraphDigest: semanticDependencyGraphDigest,
            contentIdentities: contentIdentities,
            approvalContentIdentities: approvalContentIdentities,
            qualificationContentIdentities: qualificationContentIdentities,
            retentionReceipts: retentionReceipts
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = Self(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            databaseRevisions: try container.decode(
                [ReleaseDatabaseRevisionBinding].self,
                forKey: .databaseRevisions
            ),
            semanticDependencyGraphDigest: try container.decode(
                ContentDigest.self,
                forKey: .semanticDependencyGraphDigest
            ),
            contentIdentities: try container.decode(
                [ArtifactID].self,
                forKey: .contentIdentities
            ),
            approvalContentIdentities: try container.decode(
                [ArtifactID].self,
                forKey: .approvalContentIdentities
            ),
            qualificationContentIdentities: try container.decode(
                [ArtifactID].self,
                forKey: .qualificationContentIdentities
            ),
            retentionReceipts: try container.decode(
                [DesignRevisionRetentionReceipt].self,
                forKey: .retentionReceipts
            )
        )
        try DefaultReleaseExactBundleValidator().validate(decoded)
        self = decoded
    }

    private init(
        schemaVersion: Int,
        databaseRevisions: [ReleaseDatabaseRevisionBinding],
        semanticDependencyGraphDigest: ContentDigest,
        contentIdentities: [ArtifactID],
        approvalContentIdentities: [ArtifactID],
        qualificationContentIdentities: [ArtifactID],
        retentionReceipts: [DesignRevisionRetentionReceipt]
    ) {
        self.schemaVersion = schemaVersion
        self.databaseRevisions = databaseRevisions.sorted {
            if $0.databaseRole != $1.databaseRole {
                return $0.databaseRole < $1.databaseRole
            }
            if $0.revision.databaseID != $1.revision.databaseID {
                return $0.revision.databaseID.description
                    < $1.revision.databaseID.description
            }
            return $0.revision.revisionID.description
                < $1.revision.revisionID.description
        }
        self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
        self.contentIdentities = contentIdentities.sorted {
            $0.description < $1.description
        }
        self.approvalContentIdentities = approvalContentIdentities.sorted {
            $0.description < $1.description
        }
        self.qualificationContentIdentities = qualificationContentIdentities.sorted {
            $0.description < $1.description
        }
        self.retentionReceipts = retentionReceipts.sorted {
            if $0.revision.databaseID != $1.revision.databaseID {
                return $0.revision.databaseID.description
                    < $1.revision.databaseID.description
            }
            if $0.revision.revisionID != $1.revision.revisionID {
                return $0.revision.revisionID.description
                    < $1.revision.revisionID.description
            }
            return $0.claimID.rawValue < $1.claimID.rawValue
        }
    }
}
