import CircuiteFoundation
import Foundation

/// Human review decision bound to the release-profile result artifact.
public struct FoundationReleaseProfileApproval: Sendable, Hashable, Codable {
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

    public let runID: String
    public let stageID: String
    public let verdict: Verdict
    public let reviewer: String
    public let reviewerKind: ReviewerKind
    public let note: String
    public let createdAt: Date
    public let stageResultDigest: ContentDigest?

    public init(
        runID: String,
        stageID: String,
        verdict: Verdict,
        reviewer: String,
        reviewerKind: ReviewerKind = .human,
        note: String = "",
        createdAt: Date,
        stageResultDigest: ContentDigest? = nil
    ) {
        self.runID = runID
        self.stageID = stageID
        self.verdict = verdict
        self.reviewer = reviewer
        self.reviewerKind = reviewerKind
        self.note = note
        self.createdAt = createdAt
        self.stageResultDigest = stageResultDigest
    }
}
