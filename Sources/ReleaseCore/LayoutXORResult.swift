import Foundation
import ToolQualification
import CircuiteFoundation

public struct LayoutXORResult: Sendable, Hashable, Codable {
    public var status: LayoutXORStatus
    public var method: LayoutComparisonMethod
    public var sourceDigest: String?
    public var streamedDigest: String?
    public var message: String
    public var evidenceArtifact: ArtifactReference?
    public var processQualification: ToolProcessQualificationEvidence?

    public init(
        status: LayoutXORStatus,
        method: LayoutComparisonMethod,
        sourceDigest: String? = nil,
        streamedDigest: String? = nil,
        message: String,
        evidenceArtifact: ArtifactReference? = nil,
        processQualification: ToolProcessQualificationEvidence? = nil
    ) {
        self.status = status
        self.method = method
        self.sourceDigest = sourceDigest
        self.streamedDigest = streamedDigest
        self.message = message
        self.evidenceArtifact = evidenceArtifact
        self.processQualification = processQualification
    }

    public func isTapeoutQualified(at date: Date) -> Bool {
        guard status == .passed else {
            return false
        }
        switch method {
        case .byteIdentity:
            return sourceDigest != nil && sourceDigest == streamedDigest
        case .geometricXOR:
            guard let evidenceArtifact,
                  evidenceArtifact.digest.algorithm == .sha256,
                  evidenceArtifact.byteCount > 0,
                  let producer = evidenceArtifact.producer,
                  producer.kind == .tool,
                  let processQualification,
                  processQualification.isQualified(at: date, requirePDKScope: true),
                  producer.identifier == processQualification.scope.implementationID,
                  producer.version == processQualification.scope.toolVersion,
                  processQualification.outputArtifacts.contains(evidenceArtifact) else {
                return false
            }
            return true
        }
    }
}
