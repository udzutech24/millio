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
                id: "finances.trackedTickers",
                title: isRussian ? "Отслеживаемые тикеры" : "Tracked tickers",
                location: isRussian ? "Финансы -> добавление инвест-счёта и редактор инвестиций" : "Finances -> add investment account and investment editor",
                freeBehavior: isRussian ? "До \(EntitlementPolicy.freeTrackedTickerLimit) отслеживаемых тикеров." : "Up to \(EntitlementPolicy.freeTrackedTickerLimit) tracked tickers.",
                premiumBehavior: isRussian ? "Безлимитные отслеживаемые тикеры." : "Unlimited tracked tickers.",
                isPremiumActive: appState.isPro,
                currentState: appState.isPro
                    ? (isRussian ? "Без лимита" : "Unlimited")
                    : (isRussian ? "Лимит \(EntitlementPolicy.freeTrackedTickerLimit)" : "Limit \(EntitlementPolicy.freeTrackedTickerLimit)")
            ),
            EntitlementDiagnosticItem(
                id: "quicksetup.tickers",
                title: isRussian ? "Импорт тикеров в быстрой настройке" : "Quick setup ticker import",
                location: isRussian ? "Быстрая настройка -> применение тикеров" : "Quick setup -> applying tracked tickers",
                freeBehavior: isRussian ? "Останавливается на бесплатном лимите." : "Stops at the free ticker limit.",
                premiumBehavior: isRussian ? "Применяет все тикеры." : "Applies all tracked tickers.",
                isPremiumActive: appState.isPro,
                currentState: appState.isPro
                    ? (isRussian ? "Применяет всё" : "Applies all")
                    : (isRussian ? "Применяет первые \(EntitlementPolicy.freeTrackedTickerLimit)" : "Applies first \(EntitlementPolicy.freeTrackedTickerLimit)")
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
            EntitlementDiagnosticItem(
                id: "widget.premium",
                title: isRussian ? "Премиум-виджет" : "Premium widget",
                location: isRussian ? "Виджет на домашнем экране -> премиум-конвертер" : "Home Screen widget -> premium converter widget",
                freeBehavior: isRussian ? "Показывает сообщение premium-only." : "Shows premium-only message.",
                premiumBehavior: isRussian ? "Показывает полноценный виджет-конвертер." : "Shows full converter widget.",
                isPremiumActive: appState.isPro,
                currentState: appState.isPro
                    ? (isRussian ? "Полный виджет" : "Full widget")
                    : (isRussian ? "Premium-only заглушка" : "Premium-only placeholder")
            )
        ]
    }
}
