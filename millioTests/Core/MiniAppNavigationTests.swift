import Testing

@testable import millio

@Suite(.serialized)
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

    @Test("Мини-приложение кешбэка использует локализационный ключ сервиса")
    func cashbackUsesLocalizedServiceTitle() {
        AppLanguageTestSupport.withLanguage(.simplifiedChinese) {
            let destinations = MiniAppNavigation.destinations(excluding: .courses)
            let cashback = destinations.first(where: { $0.route == .cashback })

            #expect(cashback?.titleKey == MainLocalization.serviceCashback)
            #expect(cashback?.title == MainLocalization.text(MainLocalization.serviceCashback))
        }
    }

    @Test("Мини-приложения используют стабильные акцентные цвета в quick navigation")
    func destinationsExposeStableIconTints() {
        let destinations = MiniAppNavigation.destinations(excluding: .profile)

        let byRoute = Dictionary(uniqueKeysWithValues: destinations.map { ($0.route, $0) })

        #expect(byRoute[.finances]?.iconTint == (AppColors.financesGradient.first ?? AppColors.brandPrimary))
        #expect(byRoute[.courses]?.iconTint == (AppColors.coursesGradient.first ?? AppColors.profileIconGreen))
        #expect(byRoute[.cashback]?.iconTint == AppColors.profileIconOrange)
        #expect(byRoute[.cashflow]?.iconTint == (AppColors.cashflowGradient.first ?? AppColors.profileIconPurple))
    }
}
