import CircuiteFoundation

public struct ReleaseDatabaseRevisionBinding: Sendable, Hashable, Codable {
    public let databaseRole: String
    public let revision: DesignRevisionReference

    public init(
        databaseRole: String,
        revision: DesignRevisionReference
    ) {
        self.databaseRole = databaseRole
        self.revision = revision
    }
}
