import Testing
@testable import millio

@Suite("Finance archive routing")
struct FinanceArchiveRouteTests {
    @Test func settingsExposeOneArchiveRouteForEveryStorageCombination() {
        #expect(FinanceArchiveRoute.resolve(hasCore: false, hasLegacy: false) == .none)
        #expect(FinanceArchiveRoute.resolve(hasCore: true, hasLegacy: false) == .core)
        #expect(FinanceArchiveRoute.resolve(hasCore: false, hasLegacy: true) == .legacy)
        #expect(FinanceArchiveRoute.resolve(hasCore: true, hasLegacy: true) == .split)
    }
}
