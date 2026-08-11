import Foundation
import CircuiteFoundation

public struct ReleaseArtifactPersistenceRequest: Sendable, Hashable {
    public var logicalID: String
    public var destination: ReleaseArtifactDestination
    public var bytes: Data
    public var producer: ProducerIdentity

    public init(
        logicalID: String,
        destination: ReleaseArtifactDestination,
        bytes: Data,
        producer: ProducerIdentity
    ) {
        self.logicalID = logicalID
        self.destination = destination
        self.bytes = bytes
        self.producer = producer
    }
}
