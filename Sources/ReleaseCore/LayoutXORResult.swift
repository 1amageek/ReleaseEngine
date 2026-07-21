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
    public var executionStatus: LayoutXORExecutionStatus
    public var exitCode: Int32?
    public var differenceCount: UInt64?
    public var differenceAreaSquareMicrometers: Double?
    public var rawReportDigest: ContentDigest?
    public var provenance: ExecutionProvenance?

    public init(
        status: LayoutXORStatus,
        method: LayoutComparisonMethod,
        sourceDigest: String? = nil,
        streamedDigest: String? = nil,
        message: String,
        evidenceArtifact: ArtifactReference? = nil,
        processQualification: ToolProcessQualificationEvidence? = nil,
        executionStatus: LayoutXORExecutionStatus = .notExecuted,
        exitCode: Int32? = nil,
        differenceCount: UInt64? = nil,
        differenceAreaSquareMicrometers: Double? = nil,
        rawReportDigest: ContentDigest? = nil,
        provenance: ExecutionProvenance? = nil
    ) {
        self.status = status
        self.method = method
        self.sourceDigest = sourceDigest
        self.streamedDigest = streamedDigest
        self.message = message
        self.evidenceArtifact = evidenceArtifact
        self.processQualification = processQualification
        self.executionStatus = executionStatus
        self.exitCode = exitCode
        self.differenceCount = differenceCount
        self.differenceAreaSquareMicrometers = differenceAreaSquareMicrometers
        self.rawReportDigest = rawReportDigest
        self.provenance = provenance
    }

    public func isTapeoutQualified(at date: Date) -> Bool {
        guard status == .passed else {
            return false
        }
        switch method {
        case .byteIdentity:
            return false
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
                  producer.build?.caseInsensitiveCompare(processQualification.scope.binaryDigest) == .orderedSame,
                  executionStatus == .completed,
                  exitCode == 0,
                  differenceCount == 0,
                  differenceAreaSquareMicrometers == 0,
                  differenceAreaSquareMicrometers?.isFinite == true,
                  rawReportDigest == evidenceArtifact.digest,
                  let provenance,
                  provenance.producer == producer,
                  provenance.invocation?.mode == .externalProcess,
                  provenance.environment != nil,
                  provenance.inputs.count == 2,
                  provenance.inputs.contains(where: {
                      $0.digest.hexadecimalValue.caseInsensitiveCompare(sourceDigest ?? "") == .orderedSame
                  }),
                  provenance.inputs.contains(where: {
                      $0.digest.hexadecimalValue.caseInsensitiveCompare(streamedDigest ?? "") == .orderedSame
                  }) else {
                return false
            }
            return true
        }
    }
}
