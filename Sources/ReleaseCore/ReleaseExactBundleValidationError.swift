import CircuiteFoundation

public enum ReleaseExactBundleValidationError: Error, Sendable, Hashable {
    case unsupportedSchemaVersion(actual: Int, expected: Int)
    case emptyDatabaseRevisionSet
    case invalidDatabaseRole(String)
    case duplicateDatabaseRole(String)
    case duplicateDatabase(DesignDatabaseID)
    case invalidSemanticDependencyGraphDigest(ContentDigest)
    case emptyContentIdentitySet
    case duplicateContentIdentity(ArtifactID)
    case emptyApprovalIdentitySet
    case duplicateApprovalIdentity(ArtifactID)
    case emptyQualificationIdentitySet
    case duplicateQualificationIdentity(ArtifactID)
    case recordIdentityClassificationOverlap(ArtifactID)
    case approvalIdentityNotRetained(ArtifactID)
    case qualificationIdentityNotRetained(ArtifactID)
    case retentionInventoryMismatch
    case duplicateRetentionReceipt(DesignRevisionReference)
    case inactiveRetentionReceipt(DesignRevisionReference)
    case retentionOperationDatabaseMismatch(DesignRevisionReference)
    case invalidRetentionGeneration(DesignRevisionReference)
    case invalidRetentionReachabilityGeneration(DesignRevisionReference)
    case invalidRetentionOutcomeDigest(DesignRevisionReference)
}
