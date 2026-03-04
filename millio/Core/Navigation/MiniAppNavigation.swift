import SwiftUI

struct MiniAppDestination: Equatable, Identifiable {
    let route: AppRoute
    let title: String
    let systemImage: String

    var id: String {
        title
    }
}

enum MiniAppNavigation {
    private static let allDestinations: [MiniAppDestination] = [
        MiniAppDestination(route: .finances, title: "Финансы", systemImage: "chart.pie"),
        MiniAppDestination(route: .courses, title: "Курсы", systemImage: "dollarsign.arrow.circlepath"),
        MiniAppDestination(route: .cashback, title: "Кешбэк", systemImage: "percent"),
        MiniAppDestination(route: .cashflow, title: "Кэшфлоу", systemImage: "chart.line.uptrend.xyaxis")
    ]

    static func destinations(excluding route: AppRoute) -> [MiniAppDestination] {
        allDestinations.filter { $0.route != route }
    }

    @MainActor
    static func navigate(to route: AppRoute, from currentRoute: AppRoute, router: AppRouter) {
        guard route != currentRoute else { return }
        router.navigationPath = NavigationPath()
        router.push(route)
    }
}
