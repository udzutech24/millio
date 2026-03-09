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
                id: "converter.crypto",
                title: isRussian ? "Крипта в конвертере" : "Crypto in converter",
                location: isRussian ? "Курсы -> выбор валюты и конвертер" : "Courses -> currency picker and converter",
                freeBehavior: isRussian ? "Доступны только фиатные валюты." : "Only fiat currencies are available.",
                premiumBehavior: isRussian ? "Криптовалюты разблокированы." : "Crypto currencies are unlocked.",
                isPremiumActive: EntitlementPolicy.canUseConverterCrypto(isPro: appState.isPro),
                currentState: EntitlementPolicy.canUseConverterCrypto(isPro: appState.isPro)
                    ? (isRussian ? "Открыто" : "Unlocked")
                    : (isRussian ? "Закрыто на Free" : "Locked for Free")
            ),
            EntitlementDiagnosticItem(
                id: "finances.market_assets",
                title: isRussian ? "Акции и крипта в финансах" : "Stocks & crypto in Finances",
                location: isRussian ? "Финансы -> добавление инвест-счёта и редактор инвестиций" : "Finances -> add investment account and investment editor",
                freeBehavior: isRussian ? "Недоступны без PRO." : "Locked without PRO.",
                premiumBehavior: isRussian ? "Полный доступ к рынкам." : "Full market access.",
                isPremiumActive: EntitlementPolicy.canUseFinanceStocks(isPro: appState.isPro) && EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro),
                currentState: (EntitlementPolicy.canUseFinanceStocks(isPro: appState.isPro) && EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro))
                    ? (isRussian ? "Открыто" : "Unlocked")
                    : (isRussian ? "Закрыто на Free" : "Locked for Free")
            ),
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
                title: isRussian ? "График расходов и доходов" : "Income & expenses chart",
                location: isRussian ? "Cashflow -> динамика за период" : "Cashflow -> period chart",
                freeBehavior: isRussian ? "График скрыт." : "Chart is locked.",
                premiumBehavior: isRussian ? "График доступен." : "Chart is available.",
                isPremiumActive: EntitlementPolicy.canUseCashflowChart(isPro: appState.isPro),
                currentState: EntitlementPolicy.canUseCashflowChart(isPro: appState.isPro)
                    ? (isRussian ? "Открыто" : "Unlocked")
                    : (isRussian ? "Закрыто на Free" : "Locked for Free")
            ),
            EntitlementDiagnosticItem(
                id: "cashback.cards",
                title: isRussian ? "Карты кешбэка" : "Cashback cards",
                location: isRussian ? "Кешбэк -> выбор карты и доступ к сохранённым картам" : "Cashback -> card picker and saved card access",
                freeBehavior: isRussian ? "Доступны только первые \(EntitlementPolicy.freeCashbackCardLimit) карты." : "Only first \(EntitlementPolicy.freeCashbackCardLimit) cards are available.",
                premiumBehavior: isRussian ? "Доступны все карты." : "All cards are available.",
                isPremiumActive: appState.isPro,
                currentState: appState.isPro
                    ? (isRussian ? "Все карты видны" : "All cards visible")
                    : (isRussian ? "Только первые \(EntitlementPolicy.freeCashbackCardLimit) карты" : "First \(EntitlementPolicy.freeCashbackCardLimit) cards only")
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
