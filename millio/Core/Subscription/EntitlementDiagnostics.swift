import Foundation

struct EntitlementDiagnosticItem: Identifiable, Equatable {
    let id: String
    let title: String
    let location: String
    let freeBehavior: String
    let premiumBehavior: String
    let isPremiumActive: Bool
    let currentState: String
}

enum EntitlementDiagnostics {
    @MainActor
    static func items(for appState: AppState) -> [EntitlementDiagnosticItem] {
        let locale = LocalizationSupport.resolvedLocale(
            for: appState.selectedLanguage,
            fallbackLocale: .current
        )

        return [
            EntitlementDiagnosticItem(
                id: "finances.products",
                title: localized("subscription.diagnostics.finances_products.title", locale: locale, fallback: "Products limit"),
                location: localized("subscription.diagnostics.finances_products.location", locale: locale, fallback: "Finances -> add products"),
                freeBehavior: String(
                    format: localized(
                        "subscription.diagnostics.finances_products.free_behavior_format",
                        locale: locale,
                        fallback: "Up to %lld products."
                    ),
                    locale: locale,
                    EntitlementPolicy.freeFinanceProductLimit
                ),
                premiumBehavior: localized("subscription.diagnostics.finances_products.premium_behavior", locale: locale, fallback: "Unlimited products."),
                isPremiumActive: appState.isPro,
                currentState: appState.isPro
                    ? localized("subscription.diagnostics.state.unlimited", locale: locale, fallback: "Unlimited")
                    : String(
                        format: localized("subscription.diagnostics.state.limit_format", locale: locale, fallback: "Limit %lld"),
                        locale: locale,
                        EntitlementPolicy.freeFinanceProductLimit
                    )
            ),
            EntitlementDiagnosticItem(
                id: "finances.charts",
                title: localized("subscription.diagnostics.finances_charts.title", locale: locale, fallback: "Finance charts"),
                location: localized("subscription.diagnostics.finances_charts.location", locale: locale, fallback: "Finances -> dynamics"),
                freeBehavior: localized("subscription.diagnostics.finances_charts.free_behavior", locale: locale, fallback: "Charts are locked."),
                premiumBehavior: localized("subscription.diagnostics.finances_charts.premium_behavior", locale: locale, fallback: "Charts are available."),
                isPremiumActive: EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro),
                currentState: EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro)
                    ? localized("subscription.diagnostics.state.unlocked", locale: locale, fallback: "Unlocked")
                    : localized("subscription.diagnostics.state.locked_for_free", locale: locale, fallback: "Locked for Free")
            ),
            EntitlementDiagnosticItem(
                id: "cashflow.chart",
                title: localized("subscription.diagnostics.cashflow_chart.title", locale: locale, fallback: "Income and expenses"),
                location: localized("subscription.diagnostics.cashflow_chart.location", locale: locale, fallback: "Cashflow -> period chart"),
                freeBehavior: localized("subscription.diagnostics.cashflow_chart.free_behavior", locale: locale, fallback: "Chart is locked."),
                premiumBehavior: localized("subscription.diagnostics.cashflow_chart.premium_behavior", locale: locale, fallback: "Chart is available."),
                isPremiumActive: EntitlementPolicy.canUseCashflowChart(isPro: appState.isPro),
                currentState: EntitlementPolicy.canUseCashflowChart(isPro: appState.isPro)
                    ? localized("subscription.diagnostics.state.unlocked", locale: locale, fallback: "Unlocked")
                    : localized("subscription.diagnostics.state.locked_for_free", locale: locale, fallback: "Locked for Free")
            ),
            EntitlementDiagnosticItem(
                id: "cashflow.expense_screenshot_import",
                title: localized("subscription.diagnostics.cashflow_expense_import.title", locale: locale, fallback: "Expense screenshot import"),
                location: localized("subscription.diagnostics.cashflow_expense_import.location", locale: locale, fallback: "Cashflow -> Mass import -> Screenshot mode"),
                freeBehavior: localized("subscription.diagnostics.cashflow_expense_import.free_behavior", locale: locale, fallback: "OCR import is locked."),
                premiumBehavior: localized("subscription.diagnostics.cashflow_expense_import.premium_behavior", locale: locale, fallback: "OCR import is available."),
                isPremiumActive: EntitlementPolicy.canImportCashflowExpensesFromScreenshot(isPro: appState.isPro),
                currentState: EntitlementPolicy.canImportCashflowExpensesFromScreenshot(isPro: appState.isPro)
                    ? localized("subscription.diagnostics.state.unlocked", locale: locale, fallback: "Unlocked")
                    : localized("subscription.diagnostics.state.locked_for_free", locale: locale, fallback: "Locked for Free")
            ),
            EntitlementDiagnosticItem(
                id: "cashback.categories",
                title: localized("subscription.diagnostics.cashback_categories.title", locale: locale, fallback: "Cashback categories"),
                location: localized("subscription.diagnostics.cashback_categories.location", locale: locale, fallback: "Cashback -> category editor"),
                freeBehavior: String(
                    format: localized(
                        "subscription.diagnostics.cashback_categories.free_behavior_format",
                        locale: locale,
                        fallback: "Up to %lld categories per month."
                    ),
                    locale: locale,
                    EntitlementPolicy.freeCashbackCategoryLimitPerMonth
                ),
                premiumBehavior: localized("subscription.diagnostics.cashback_categories.premium_behavior", locale: locale, fallback: "Unlimited categories."),
                isPremiumActive: appState.isPro,
                currentState: appState.isPro
                    ? localized("subscription.diagnostics.state.unlimited", locale: locale, fallback: "Unlimited")
                    : String(
                        format: localized("subscription.diagnostics.state.limit_format", locale: locale, fallback: "Limit %lld"),
                        locale: locale,
                        EntitlementPolicy.freeCashbackCategoryLimitPerMonth
                    )
            ),
            EntitlementDiagnosticItem(
                id: "cashback.screenshot",
                title: localized("subscription.diagnostics.cashback_import.title", locale: locale, fallback: "Cashback screenshot import"),
                location: localized("subscription.diagnostics.cashback_import.location", locale: locale, fallback: "Cashback -> screenshot import CTA"),
                freeBehavior: localized("subscription.diagnostics.cashback_import.free_behavior", locale: locale, fallback: "Import is locked."),
                premiumBehavior: localized("subscription.diagnostics.cashback_import.premium_behavior", locale: locale, fallback: "Import is available."),
                isPremiumActive: EntitlementPolicy.canImportCashbackFromScreenshot(isPro: appState.isPro),
                currentState: EntitlementPolicy.canImportCashbackFromScreenshot(isPro: appState.isPro)
                    ? localized("subscription.diagnostics.state.unlocked", locale: locale, fallback: "Unlocked")
                    : localized("subscription.diagnostics.state.locked_for_free", locale: locale, fallback: "Locked for Free")
            ),
        ]
    }

    private static func localized(_ key: String, locale: Locale, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }
}
