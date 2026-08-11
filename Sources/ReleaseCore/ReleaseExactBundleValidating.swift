public protocol ReleaseExactBundleValidating: Sendable {
    func validate(
        _ bundle: ReleaseExactBundle
    ) throws(ReleaseExactBundleValidationError)
}
