import Testing
@testable import ReleaseCore
@testable import SignoffEngine
@testable import TapeoutEngine
@testable import ReleaseEngine

@Suite("ReleaseEngine contract")
struct ContractTests {
    @Test("contract version starts at one")
    func contractVersion() {
        #expect(ReleaseEngineAPI.contractVersion == 1)
    }
}
