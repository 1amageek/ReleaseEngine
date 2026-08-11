import CircuiteFoundation
import Foundation
import ReleaseCore
import Testing

@Suite("Local release artifact access")
struct LocalReleaseArtifactStoreTests {
    @Test("relocating a root preserves content identity and verified access")
    func relocationPreservesIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let binding = try await fixture.persist(Data("release".utf8))

        try FileManager.default.moveItem(
            at: fixture.originalRoot,
            to: fixture.relocatedRoot
        )
        let loaded = try await fixture.store.load(
            binding,
            relativeTo: fixture.relocatedRoot
        )

        #expect(loaded == Data("release".utf8))
        #expect(binding.reference.id == binding.availability.artifactID)
    }

    @Test("tampered bytes fail with a typed integrity error")
    func tamperedBytesFailIntegrity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let binding = try await fixture.persist(Data("alpha".utf8))
        let artifactURL = fixture.originalRoot.appending(
            path: fixture.relativePath.stringValue
        )
        try FileManager.default.removeItem(at: artifactURL)
        try Data("omega".utf8).write(to: artifactURL)

        await #expect(throws: LocalReleaseArtifactStoreError.readIntegrityFailed(
            fixture.relativePath.stringValue
        )) {
            _ = try await fixture.store.load(
                binding,
                relativeTo: fixture.originalRoot
            )
        }
    }

    @Test("a symbolic-link replacement cannot escape the admitted root")
    func symbolicLinkReplacementFails() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let binding = try await fixture.persist(Data("alpha".utf8))
        let artifactURL = fixture.originalRoot.appending(
            path: fixture.relativePath.stringValue
        )
        let outside = fixture.parent.appending(path: "outside.json")
        try Data("alpha".utf8).write(to: outside)
        try FileManager.default.removeItem(at: artifactURL)
        try FileManager.default.createSymbolicLink(
            at: artifactURL,
            withDestinationURL: outside
        )

        await #expect(throws: LocalReleaseArtifactStoreError.invalidLocation(
            fixture.relativePath.stringValue
        )) {
            _ = try await fixture.store.load(
                binding,
                relativeTo: fixture.originalRoot
            )
        }
    }

    @Test("the bounded reader rejects content beyond its total-byte budget")
    func readBudgetIsEnforced() async throws {
        let budget = try ArtifactAccessBudget(
            maximumPageByteCount: 4,
            maximumTotalByteCount: 8,
            maximumPageCount: 2,
            maximumWorkUnitCount: 2,
            maximumDurationNanoseconds: 1_000_000_000
        )
        let fixture = try Fixture(store: LocalReleaseArtifactStore(
            readBudget: budget
        ))
        defer { fixture.remove() }
        let binding = try await fixture.persist(Data(repeating: 0x41, count: 16))

        await #expect(throws: LocalReleaseArtifactStoreError.readBudgetExceeded(
            fixture.relativePath.stringValue
        )) {
            _ = try await fixture.store.load(
                binding,
                relativeTo: fixture.originalRoot
            )
        }
    }

    private struct Fixture {
        let parent: URL
        let originalRoot: URL
        let relocatedRoot: URL
        let relativePath: ArtifactRelativePath
        let store: LocalReleaseArtifactStore

        init(store: LocalReleaseArtifactStore = LocalReleaseArtifactStore()) throws {
            parent = FileManager.default.temporaryDirectory.appending(
                path: "release-artifact-access-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            originalRoot = parent.appending(
                path: "original",
                directoryHint: .isDirectory
            )
            relocatedRoot = parent.appending(
                path: "relocated",
                directoryHint: .isDirectory
            )
            relativePath = try ArtifactRelativePath(
                segments: ["release", "artifact.json"]
            )
            self.store = store
            try FileManager.default.createDirectory(
                at: originalRoot,
                withIntermediateDirectories: true
            )
        }

        func persist(_ data: Data) async throws -> ReleaseArtifactBinding {
            try await store.persist(
                ReleaseArtifactPersistenceRequest(
                    logicalID: "release-artifact",
                    destination: ReleaseArtifactDestination(
                        rootID: try ArtifactRootID(
                            rawValue: "release-artifact-test-root"
                        ),
                        relativePath: relativePath,
                        descriptor: ArtifactDescriptor(
                            role: .output,
                            kind: .release,
                            format: .json
                        )
                    ),
                    bytes: data,
                    producer: try ProducerIdentity(
                        kind: .engine,
                        identifier: "release-artifact-test",
                        version: "1.0.0"
                    )
                ),
                relativeTo: originalRoot
            )
        }

        func remove() {
            do {
                try FileManager.default.removeItem(at: parent)
            } catch {
                Issue.record(
                    "Failed to remove release artifact fixture: \(error.localizedDescription)"
                )
            }
        }
    }
}
