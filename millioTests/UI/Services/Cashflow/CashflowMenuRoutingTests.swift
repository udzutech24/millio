import Testing
@testable import millio

@Suite("Cashflow menu routing")
struct CashflowMenuRoutingTests {
    @Test("Every Cashflow destination has exactly one primary owner")
    func destinationsHaveUniqueOwners() {
        #expect(Set(CashflowNavigationPolicy.ownerByDestination.keys) == Set(CashflowDestination.allCases))
        #expect(CashflowNavigationPolicy.ownerByDestination.count == CashflowDestination.allCases.count)
    }

    @Test("Overflow owns only infrequent currency settings")
    func overflowHasNoNavigationDestinations() {
        let overflowDestinations = CashflowNavigationPolicy.ownerByDestination
            .filter { $0.value == .overflow }
            .map(\.key)
        #expect(overflowDestinations == [.currency])
    }

    @Test("Cashflow route graph is acyclic and child month cannot open dashboard")
    func routeGraphIsAcyclic() {
        #expect(CashflowNavigationPolicy.isAcyclic())
        #expect(!CashflowNavigationPolicy.routeGraph[.monthOperations, default: []].contains(.dashboard))
    }
}
