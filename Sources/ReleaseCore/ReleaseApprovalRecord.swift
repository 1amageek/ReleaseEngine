import Foundation

/// Approval record used by release-profile eligibility.
///
/// Flow persistence owns the lifecycle of approvals. ReleaseCore only models
/// the domain data required to evaluate a release decision.
public struct ReleaseApprovalRecord: Sendable, Hashable, Codable {
    public enum Verdict: String, Sendable, Hashable, Codable {
        case approved
        case rejected
    }

    public enum ReviewerKind: String, Sendable, Hashable, Codable {
        case human
        case agent
        case cli
        case system
    }

    public var runID: String
    public var stageID: String
    public var verdict: Verdict
    public var reviewer: String
    public var reviewerKind: ReviewerKind
    public var note: String
    public var createdAt: Date
    public var planSHA256: String?
    public var planByteCount: Int64?
    public var stageResultSHA256: String?
    public var stageResultByteCount: Int64?

    public init(
        runID: String,
        stageID: String,
        verdict: Verdict,
        reviewer: String,
        reviewerKind: ReviewerKind = .human,
        note: String = "",
        createdAt: Date = Date(),
        planSHA256: String? = nil,
        planByteCount: Int64? = nil,
        stageResultSHA256: String? = nil,
        stageResultByteCount: Int64? = nil
    ) {
        self.runID = runID
        self.stageID = stageID
        self.verdict = verdict
        self.reviewer = reviewer
        self.reviewerKind = reviewerKind
        self.note = note
        self.createdAt = createdAt
        self.planSHA256 = planSHA256
        self.planByteCount = planByteCount
        self.stageResultSHA256 = stageResultSHA256
        self.stageResultByteCount = stageResultByteCount
    }
}
