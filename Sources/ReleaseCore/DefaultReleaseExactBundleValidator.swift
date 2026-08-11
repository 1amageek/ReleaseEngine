import CircuiteFoundation
import DesignDatabaseCore

public struct DefaultReleaseExactBundleValidator: ReleaseExactBundleValidating {
    public init() {}

    public func validate(
        _ bundle: ReleaseExactBundle
    ) throws(ReleaseExactBundleValidationError) {
        guard bundle.schemaVersion == ReleaseExactBundle.currentSchemaVersion else {
            throw .unsupportedSchemaVersion(
                actual: bundle.schemaVersion,
                expected: ReleaseExactBundle.currentSchemaVersion
            )
        }
        guard !bundle.databaseRevisions.isEmpty else {
            throw .emptyDatabaseRevisionSet
        }

        var roles = Set<String>()
        var databases = Set<DesignDatabaseID>()
        for binding in bundle.databaseRevisions {
            guard Self.isValidToken(binding.databaseRole) else {
                throw .invalidDatabaseRole(binding.databaseRole)
            }
            guard roles.insert(binding.databaseRole).inserted else {
                throw .duplicateDatabaseRole(binding.databaseRole)
            }
            guard databases.insert(binding.revision.databaseID).inserted else {
                throw .duplicateDatabase(binding.revision.databaseID)
            }
        }

        guard bundle.semanticDependencyGraphDigest.algorithm == .sha256 else {
            throw .invalidSemanticDependencyGraphDigest(
                bundle.semanticDependencyGraphDigest
            )
        }
        try validateContentIdentities(bundle)
        try validateRetentionReceipts(bundle)
    }

    private func validateContentIdentities(
        _ bundle: ReleaseExactBundle
    ) throws(ReleaseExactBundleValidationError) {
        guard !bundle.contentIdentities.isEmpty else {
            throw .emptyContentIdentitySet
        }
        guard !bundle.approvalContentIdentities.isEmpty else {
            throw .emptyApprovalIdentitySet
        }
        guard !bundle.qualificationContentIdentities.isEmpty else {
            throw .emptyQualificationIdentitySet
        }

        let retained = Set(bundle.contentIdentities)
        guard retained.count == bundle.contentIdentities.count else {
            let duplicate = Self.firstDuplicate(in: bundle.contentIdentities)!
            throw .duplicateContentIdentity(duplicate)
        }
        if let duplicate = Self.firstDuplicate(
            in: bundle.approvalContentIdentities
        ) {
            throw .duplicateApprovalIdentity(duplicate)
        }
        if let duplicate = Self.firstDuplicate(
            in: bundle.qualificationContentIdentities
        ) {
            throw .duplicateQualificationIdentity(duplicate)
        }
        if let overlap = Set(bundle.approvalContentIdentities)
            .intersection(bundle.qualificationContentIdentities)
            .first {
            throw .recordIdentityClassificationOverlap(overlap)
        }
        for identity in bundle.approvalContentIdentities
        where !retained.contains(identity) {
            throw .approvalIdentityNotRetained(identity)
        }
        for identity in bundle.qualificationContentIdentities
        where !retained.contains(identity) {
            throw .qualificationIdentityNotRetained(identity)
        }
    }

    private func validateRetentionReceipts(
        _ bundle: ReleaseExactBundle
    ) throws(ReleaseExactBundleValidationError) {
        let expectedRevisions = Set(bundle.databaseRevisions.map(\.revision))
        var retainedRevisions = Set<DesignRevisionReference>()
        for receipt in bundle.retentionReceipts {
            guard retainedRevisions.insert(receipt.revision).inserted else {
                throw .duplicateRetentionReceipt(receipt.revision)
            }
            guard receipt.state == .active else {
                throw .inactiveRetentionReceipt(receipt.revision)
            }
            guard receipt.operation.databaseID == receipt.revision.databaseID else {
                throw .retentionOperationDatabaseMismatch(receipt.revision)
            }
            guard receipt.generation > 0 else {
                throw .invalidRetentionGeneration(receipt.revision)
            }
            guard receipt.reachabilityGeneration > 0 else {
                throw .invalidRetentionReachabilityGeneration(receipt.revision)
            }
            guard receipt.outcomeDigest.algorithm == .sha256 else {
                throw .invalidRetentionOutcomeDigest(receipt.revision)
            }
        }
        guard retainedRevisions == expectedRevisions,
              bundle.retentionReceipts.count == expectedRevisions.count else {
            throw .retentionInventoryMismatch
        }
    }

    private static func isValidToken(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 256,
              value.first?.isWhitespace != true,
              value.last?.isWhitespace != true else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            $0.value >= 0x20 && !(0x7f...0x9f).contains($0.value)
        }
    }

    private static func firstDuplicate<Element: Hashable>(
        in elements: [Element]
    ) -> Element? {
        var observed = Set<Element>()
        for element in elements where !observed.insert(element).inserted {
            return element
        }
        return nil
    }
}
