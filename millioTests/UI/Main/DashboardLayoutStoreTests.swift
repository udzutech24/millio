import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct DashboardLayoutStoreTests {
    private func makeStore() -> (store: DashboardLayoutStore, defaults: UserDefaults, cleanup: () -> Void) {
        let suiteName = "DashboardLayoutStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let cleanup = {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return (DashboardLayoutStore(defaults: defaults), defaults, cleanup)
    }

    @Test("Dashboard layout store returns full default widget set")
    func loadDefaults() {
        let isolated = makeStore()
        defer { isolated.cleanup() }

        let kinds = isolated.store.load().map(\.kind)

        #expect(kinds == [.converter, .quickActions, .finances, .services, .cashflow])
    }

    @Test("Dashboard layout normalization re-adds missing widgets and removes duplicates")
    func normalizeRepairsBrokenPayload() {
        let configs = DashboardLayoutStore.normalize([
            DashboardWidgetConfig(kind: .services, isVisible: false, order: 5),
            DashboardWidgetConfig(kind: .services, isVisible: true, order: 1)
        ])

        #expect(configs.map(\.kind) == [.converter, .quickActions, .finances, .services, .cashflow])
        #expect(configs.contains(where: { $0.kind == .finances }))
        #expect(configs.count == 5)
        #expect(configs[3].isVisible == true)
    }

    @Test("Dashboard layout store persists widget order and visibility")
    func saveAndLoad() {
        let isolated = makeStore()
        defer { isolated.cleanup() }

        isolated.store.save([
            DashboardWidgetConfig(kind: .services, isVisible: true, order: 0),
            DashboardWidgetConfig(kind: .finances, isVisible: true, order: 1),
            DashboardWidgetConfig(kind: .quickActions, isVisible: false, order: 2),
            DashboardWidgetConfig(kind: .converter, isVisible: true, order: 3),
            DashboardWidgetConfig(kind: .cashflow, isVisible: false, order: 4)
        ])

        let loaded = isolated.store.load()

        #expect(loaded.map(\.kind) == [.services, .finances, .quickActions, .converter, .cashflow])
        #expect(loaded.first?.isVisible == true)
        #expect(loaded[2].isVisible == false)
        #expect(loaded[4].isVisible == false)
    }

    @Test("Dashboard layout normalization preserves drag-and-drop order from the edited list")
    func normalizePreservesIncomingArrayOrder() {
        let moved = DashboardLayoutStore.normalize([
            DashboardWidgetConfig(kind: .services, isVisible: true, order: 3),
            DashboardWidgetConfig(kind: .quickActions, isVisible: true, order: 0),
            DashboardWidgetConfig(kind: .converter, isVisible: true, order: 1),
            DashboardWidgetConfig(kind: .finances, isVisible: true, order: 2),
            DashboardWidgetConfig(kind: .cashflow, isVisible: true, order: 4)
        ])

        #expect(moved.map(\.kind) == [.services, .quickActions, .converter, .finances, .cashflow])
        #expect(moved.map(\.order) == [0, 1, 2, 3, 4])
    }
}
