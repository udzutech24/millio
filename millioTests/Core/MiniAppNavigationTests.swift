import Testing

@testable import millio

struct MiniAppNavigationTests {
    @Test("Мини-приложения исключают текущий экран")
    func excludesCurrentRoute() {
        let destinations = MiniAppNavigation.destinations(excluding: .courses)

        #expect(destinations.count == 3)
        #expect(destinations.contains(where: { $0.route == .finances }))
        #expect(destinations.contains(where: { $0.route == .cashback }))
        #expect(destinations.contains(where: { $0.route == .cashflow }))
        #expect(!destinations.contains(where: { $0.route == .courses }))
    }

    @Test("Мини-приложения сохраняют предсказуемый порядок")
    func keepsExpectedOrder() {
        let destinations = MiniAppNavigation.destinations(excluding: .cashback)

        #expect(destinations.map(\.route) == [.finances, .courses, .cashflow])
    }
}
