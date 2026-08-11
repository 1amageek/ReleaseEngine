public protocol ReleaseExactBundleBuilding: Sendable {
    func build(
        _ request: ReleaseExactBundleBuildRequest
    ) throws(ReleaseExactBundleBuildError) -> ReleaseExactBundle
}
