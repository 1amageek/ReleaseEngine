import CircuiteFoundation

public struct ReleaseArtifactDestination: Sendable, Hashable, Codable {
    public let rootID: ArtifactRootID
    public let relativePath: ArtifactRelativePath
    public let descriptor: ArtifactDescriptor

    public init(
        rootID: ArtifactRootID,
        relativePath: ArtifactRelativePath,
        descriptor: ArtifactDescriptor
    ) {
        self.rootID = rootID
        self.relativePath = relativePath
        self.descriptor = descriptor
    }

    public var materializationDescription: String {
        "local:\(rootID.rawValue)/\(relativePath.stringValue)"
    }
}
