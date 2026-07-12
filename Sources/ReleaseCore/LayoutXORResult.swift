import Foundation

public struct LayoutXORResult: Sendable, Hashable, Codable {
    public var status: LayoutXORStatus
    public var method: String
    public var sourceDigest: String?
    public var streamedDigest: String?
    public var message: String

    public init(
        status: LayoutXORStatus,
        method: String,
        sourceDigest: String? = nil,
        streamedDigest: String? = nil,
        message: String
    ) {
        self.status = status
        self.method = method
        self.sourceDigest = sourceDigest
        self.streamedDigest = streamedDigest
        self.message = message
    }
}
