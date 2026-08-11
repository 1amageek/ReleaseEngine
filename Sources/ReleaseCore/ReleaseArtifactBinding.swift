import CircuiteFoundation
import Foundation

public enum ReleaseArtifactBindingError: Error, Sendable, Equatable {
    case emptyLogicalID
    case availabilityIdentityMismatch
    case missingBinding(ArtifactID)
}

public struct ReleaseArtifactBinding: Sendable, Hashable, Codable {
    public let logicalID: String
    public let reference: ArtifactReference
    public let availability: ArtifactAvailability

    public init(
        logicalID: String,
        reference: ArtifactReference,
        availability: ArtifactAvailability
    ) throws {
        guard !logicalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReleaseArtifactBindingError.emptyLogicalID
        }
        guard reference.id == availability.artifactID else {
            throw ReleaseArtifactBindingError.availabilityIdentityMismatch
        }
        self.logicalID = logicalID
        self.reference = reference
        self.availability = availability
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            logicalID: container.decode(String.self, forKey: .logicalID),
            reference: container.decode(ArtifactReference.self, forKey: .reference),
            availability: container.decode(ArtifactAvailability.self, forKey: .availability)
        )
    }

    public var descriptor: ArtifactDescriptor { reference.descriptor }

    public var materializationDescription: String {
        switch availability {
        case .local(_, let rootID, let relativePath):
            "local:\(rootID.rawValue)/\(relativePath.stringValue)"
        case .service(_, let resource):
            "service:\(resource)"
        }
    }

    public static func require(
        _ reference: ArtifactReference,
        in bindings: [ReleaseArtifactBinding]
    ) throws -> ReleaseArtifactBinding {
        guard let binding = bindings.first(where: { $0.reference == reference }) else {
            throw ReleaseArtifactBindingError.missingBinding(reference.id)
        }
        return binding
    }
}
