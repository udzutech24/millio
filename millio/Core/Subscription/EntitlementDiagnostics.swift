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
        let isRussian = (appState.selectedLanguage.locale ?? Locale.current).identifier.hasPrefix("ru")

        return [
            EntitlementDiagnosticItem(
                id: "finances.products",
                title: isRussian ? "Лимит продуктов" : "Products limit",
                location: isRussian ? "Финансы -> добавление продуктов" : "Finances -> add products",
                freeBehavior: isRussian ? "До \(EntitlementPolicy.freeFinanceProductLimit) продуктов." : "Up to \(EntitlementPolicy.freeFinanceProductLimit) products.",
                premiumBehavior: isRussian ? "Безлимит продуктов." : "Unlimited products.",
                isPremiumActive: appState.isPro,
                currentState: appState.isPro
                    ? (isRussian ? "Без лимита" : "Unlimited")
                    : (isRussian ? "Лимит \(EntitlementPolicy.freeFinanceProductLimit)" : "Limit \(EntitlementPolicy.freeFinanceProductLimit)")
            ),
            EntitlementDiagnosticItem(
                id: "finances.charts",
                title: isRussian ? "Графики в финансах" : "Finance charts",
                location: isRussian ? "Финансы -> динамика" : "Finances -> dynamics",
                freeBehavior: isRussian ? "Графики скрыты." : "Charts are locked.",
                premiumBehavior: isRussian ? "Графики доступны." : "Charts are available.",
                isPremiumActive: EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro),
                currentState: EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro)
                    ? (isRussian ? "Открыто" : "Unlocked")
                    : (isRussian ? "Закрыто на Free" : "Locked for Free")
            ),
            EntitlementDiagnosticItem(
                id: "cashflow.chart",
                title: isRussian ? "Доходы и расходы" : "Income and expenses",
                location: isRussian ? "Cashflow -> динамика за период" : "Cashflow -> period chart",
                freeBehavior: isRussian ? "График скрыт." : "Chart is locked.",
                premiumBehavior: isRussian ? "График доступен." : "Chart is available.",
                isPremiumActive: EntitlementPolicy.canUseCashflowChart(isPro: appState.isPro),
                currentState: EntitlementPolicy.canUseCashflowChart(isPro: appState.isPro)
                    ? (isRussian ? "Открыто" : "Unlocked")
                    : (isRussian ? "Закрыто на Free" : "Locked for Free")
            ),
            EntitlementDiagnosticItem(
                id: "cashflow.expense_screenshot_import",
                title: isRussian ? "Импорт расходов со скриншота" : "Expense screenshot import",
                location: isRussian ? "Cashflow -> Mass import -> режим Screenshot" : "Cashflow -> Mass import -> Screenshot mode",
                freeBehavior: isRussian ? "OCR-импорт закрыт." : "OCR import is locked.",
                premiumBehavior: isRussian ? "OCR-импорт доступен." : "OCR import is available.",
                isPremiumActive: EntitlementPolicy.canImportCashflowExpensesFromScreenshot(isPro: appState.isPro),
                currentState: EntitlementPolicy.canImportCashflowExpensesFromScreenshot(isPro: appState.isPro)
                    ? (isRussian ? "Открыто" : "Unlocked")
                    : (isRussian ? "Закрыто на Free" : "Locked for Free")
            ),
            EntitlementDiagnosticItem(
                id: "cashback.categories",
                title: isRussian ? "Категории кешбэка" : "Cashback categories",
                location: isRussian ? "Кешбэк -> добавление категорий" : "Cashback -> category editor",
                freeBehavior: isRussian ? "До \(EntitlementPolicy.freeCashbackCategoryLimitPerMonth) категорий в месяц." : "Up to \(EntitlementPolicy.freeCashbackCategoryLimitPerMonth) categories per month.",
                premiumBehavior: isRussian ? "Безлимит категорий." : "Unlimited categories.",
                isPremiumActive: appState.isPro,
                currentState: appState.isPro
                    ? (isRussian ? "Без лимита" : "Unlimited")
                    : (isRussian ? "Лимит \(EntitlementPolicy.freeCashbackCategoryLimitPerMonth)" : "Limit \(EntitlementPolicy.freeCashbackCategoryLimitPerMonth)")
            ),
            EntitlementDiagnosticItem(
                id: "cashback.screenshot",
                title: isRussian ? "Импорт кешбэка со скриншота" : "Cashback screenshot import",
                location: isRussian ? "Кешбэк -> кнопка импорта со скриншота" : "Cashback -> screenshot import CTA",
                freeBehavior: isRussian ? "Импорт закрыт." : "Import is locked.",
                premiumBehavior: isRussian ? "Импорт доступен." : "Import is available.",
                isPremiumActive: EntitlementPolicy.canImportCashbackFromScreenshot(isPro: appState.isPro),
                currentState: EntitlementPolicy.canImportCashbackFromScreenshot(isPro: appState.isPro)
                    ? (isRussian ? "Открыто" : "Unlocked")
                    : (isRussian ? "Закрыто на Free" : "Locked for Free")
            ),
        ]
    }
}
