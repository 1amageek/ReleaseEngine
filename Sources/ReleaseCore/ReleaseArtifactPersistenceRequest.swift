import Foundation
import CircuiteFoundation

public struct ReleaseArtifactPersistenceRequest: Sendable, Hashable {
    public var locator: ArtifactLocator
    public var bytes: Data
    public var producer: ProducerIdentity

    public init(
        locator: ArtifactLocator,
        bytes: Data,
        producer: ProducerIdentity
    ) {
        self.locator = locator
        self.bytes = bytes
        self.producer = producer
    }
}
