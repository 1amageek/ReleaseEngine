import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import ToolQualification

actor TestToolQualificationArtifactReader: ToolQualificationArtifactReading {
    private let root: URL
    private let availabilities: [ArtifactID: ArtifactAvailability]

    init(
        root: URL,
        availabilities: [ArtifactID: ArtifactAvailability]
    ) {
        self.root = root
        self.availabilities = availabilities
    }

    func verifiedData(for reference: ArtifactReference) async throws -> Data {
        guard let availability = availabilities[reference.id] else {
            throw ToolProcessQualificationEvidenceBuildError
                .artifactAvailabilityMissing(reference.id.description)
        }
        guard case .local(let artifactID, _, let relativePath) = availability,
              artifactID == reference.id else {
            throw ToolProcessQualificationEvidenceBuildError.artifactAccessFailed(
                "The test artifact availability does not match its content identity."
            )
        }
        let data = try Data(
            contentsOf: root.appending(path: relativePath.stringValue),
            options: .mappedIfSafe
        )
        guard UInt64(data.count) == reference.byteCount,
              try SHA256ContentDigester().digest(data: data) == reference.digest else {
            throw ToolProcessQualificationEvidenceBuildError.artifactIntegrityFailed(
                reference.id.description
            )
        }
        return data
    }
}
