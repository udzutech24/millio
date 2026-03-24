import SwiftUI

struct MiniAppDestination: Equatable, Identifiable {
    let route: AppRoute
    /// Localization key for destination title.
    let titleKey: String
    let systemImage: String

    var title: String {
        MainLocalization.text(titleKey)
    }

    var id: String {
        switch route {
        case .finances:
            return "finances"
        case .courses:
            return "courses"
        case .cashback:
            return "cashback"
        case .cashflow:
            return "cashflow"
        default:
            return systemImage
        }
    }

    var iconTint: Color {
        switch route {
        case .finances:
            return AppColors.financesGradient.first ?? AppColors.brandPrimary
        case .courses:
            return AppColors.coursesGradient.first ?? AppColors.profileIconGreen
        case .cashback:
            return AppColors.profileIconOrange
        case .cashflow:
            return AppColors.cashflowGradient.first ?? AppColors.profileIconPurple
        default:
            return AppColors.textSecondary
        }
    }
}

enum MiniAppNavigation {
    private static let allDestinations: [MiniAppDestination] = [
        MiniAppDestination(route: .finances, titleKey: MainLocalization.serviceFinances, systemImage: "chart.pie"),
        MiniAppDestination(route: .courses, titleKey: MainLocalization.serviceCourses, systemImage: "dollarsign.arrow.circlepath"),
        MiniAppDestination(route: .cashback, titleKey: MainLocalization.serviceCashback, systemImage: "percent"),
        MiniAppDestination(route: .cashflow, titleKey: MainLocalization.serviceCashflow, systemImage: "chart.line.uptrend.xyaxis")
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
