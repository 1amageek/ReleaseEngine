import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public struct DefaultReleaseExactBundleBuilder: ReleaseExactBundleBuilding {
    private let validator: any ReleaseExactBundleValidating
    private let digester: any ContentDigesting

    public init(
        validator: any ReleaseExactBundleValidating = DefaultReleaseExactBundleValidator(),
        digester: any ContentDigesting = SHA256ContentDigester()
    ) {
        self.validator = validator
        self.digester = digester
    }

    public func build(
        _ request: ReleaseExactBundleBuildRequest
    ) throws(ReleaseExactBundleBuildError) -> ReleaseExactBundle {
        try validateOwnerOutputs(request)
        let inventory = ReleaseExactContentInventory(request: request)
        let bundle = ReleaseExactBundle(
            databaseRevisions: request.databaseRevisions,
            semanticDependencyGraphDigest: request.semanticDependencyGraphDigest,
            contentIdentities: inventory.contentIdentities,
            approvalContentIdentities: inventory.approvalContentIdentities,
            qualificationContentIdentities: inventory.qualificationContentIdentities,
            retentionReceipts: request.retentionReceipts
        )
        do {
            try validator.validate(bundle)
        } catch {
            throw .invalidBundle(error)
        }
        return bundle
    }

    private func validateOwnerOutputs(
        _ request: ReleaseExactBundleBuildRequest
    ) throws(ReleaseExactBundleBuildError) {
        guard request.signoffBundle.isReleaseReady else {
            throw .signoffBundleNotReleaseReady
        }
        let reference = request.signoffBundleReference
        guard reference.designDigest == request.signoffBundle.designDigest else {
            throw .signoffReferenceMismatch(field: "design digest")
        }
        guard reference.pdkDigest == request.signoffBundle.pdkDigest else {
            throw .signoffReferenceMismatch(field: "PDK digest")
        }
        guard reference.finalLayoutDigest == request.signoffBundle.finalLayoutDigest else {
            throw .signoffReferenceMismatch(field: "final layout digest")
        }

        let canonicalData: Data
        let canonicalDigest: ContentDigest
        do {
            canonicalData = try request.signoffBundle.canonicalData()
            canonicalDigest = try digester.digest(data: canonicalData, using: .sha256)
        } catch {
            throw .signoffArtifactIdentityMismatch
        }
        let signoffArtifact = reference.artifact.reference
        guard signoffArtifact.digest == canonicalDigest,
              signoffArtifact.byteCount == UInt64(canonicalData.count) else {
            throw .signoffArtifactIdentityMismatch
        }

        guard request.approval.verdict != .rejected else {
            throw .approvalRejected
        }
        guard request.approval.evidence.stageResult.reference
                == reference.artifact.reference else {
            throw .approvalSignoffArtifactMismatch
        }
    }
}
