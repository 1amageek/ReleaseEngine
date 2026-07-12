import Foundation
import ReleaseCore
import XcircuitePackage

public protocol LayoutXORComparing: Sendable {
    func compare(
        source: XcircuiteFileReference,
        streamed: XcircuiteFileReference,
        projectRoot: URL?
    ) -> LayoutXORResult
}
