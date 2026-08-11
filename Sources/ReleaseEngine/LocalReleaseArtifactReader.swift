import DesignFlowKernel
import Foundation
import ReleaseCore

public actor LocalReleaseArtifactReader: ReleaseAuthorizationArtifactReading {
    private let workspaceRoot: URL
    private let reader: any ReleaseArtifactReading

    public init(
        workspaceRoot: URL,
        reader: any ReleaseArtifactReading = LocalReleaseArtifactStore()
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.reader = reader
    }

    public func verifiedData(
        for binding: ReleaseArtifactBinding
    ) async throws -> Data {
        try await reader.load(binding, relativeTo: workspaceRoot)
    }

    public func verifiedData(
        for binding: FlowArtifactBinding
    ) async throws -> Data {
        let releaseBinding = try ReleaseArtifactBinding(
            logicalID: binding.logicalID,
            reference: binding.reference,
            availability: binding.availability
        )
        return try await reader.load(releaseBinding, relativeTo: workspaceRoot)
    }
}
