import CircuiteFoundation
import Foundation
import ReleaseCore
import ToolQualification

struct ReleaseToolQualificationArtifactReader: ToolQualificationArtifactReading {
    private let bindingsByID: [ArtifactID: ReleaseArtifactBinding]
    private let reader: any ReleaseAuthorizationArtifactReading

    init(
        bindings: [ReleaseArtifactBinding],
        reader: any ReleaseAuthorizationArtifactReading
    ) {
        var bindingsByID: [ArtifactID: ReleaseArtifactBinding] = [:]
        for binding in bindings where bindingsByID[binding.reference.id] == nil {
            bindingsByID[binding.reference.id] = binding
        }
        self.bindingsByID = bindingsByID
        self.reader = reader
    }

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let binding = bindingsByID[reference.id],
              binding.reference == reference else {
            throw ReleaseToolQualificationArtifactReaderError.bindingMissing(
                reference.id
            )
        }
        return try await reader.verifiedData(for: binding)
    }
}
