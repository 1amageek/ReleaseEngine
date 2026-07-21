import Foundation

public struct LayoutXORReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let differenceCount: UInt64
    public let differenceAreaSquareMicrometers: Double

    public init(
        differenceCount: UInt64,
        differenceAreaSquareMicrometers: Double,
        schemaVersion: Int = Self.currentSchemaVersion
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LayoutXORReportError.unsupportedSchemaVersion(schemaVersion)
        }
        guard differenceAreaSquareMicrometers.isFinite,
              differenceAreaSquareMicrometers >= 0 else {
            throw LayoutXORReportError.invalidDifferenceArea(differenceAreaSquareMicrometers)
        }
        self.schemaVersion = schemaVersion
        self.differenceCount = differenceCount
        self.differenceAreaSquareMicrometers = differenceAreaSquareMicrometers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            differenceCount: container.decode(UInt64.self, forKey: .differenceCount),
            differenceAreaSquareMicrometers: container.decode(
                Double.self,
                forKey: .differenceAreaSquareMicrometers
            ),
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion)
        )
    }

    public func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
