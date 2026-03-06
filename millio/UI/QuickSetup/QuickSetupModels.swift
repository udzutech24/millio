import Foundation

enum QuickSetupStep: Int, CaseIterable, Identifiable {
    case localeAndCurrencies
    case expenseCategories
    case products
    case summary

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .localeAndCurrencies:
            return "Язык и валюты"
        case .expenseCategories:
            return "Категории трат"
        case .products:
            return "Добавить продукты"
        case .summary:
            return "Готово"
        }
    }
}

enum QuickSetupProductType: String, CaseIterable, Identifiable {
    case card
    case realEstate
    case debt
    case crypto
    case credit
    case ticker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: return "Карта"
        case .realEstate: return "Недвиж."
        case .debt: return "Долг"
        case .crypto: return "Крипто"
        case .credit: return "Кредит"
        case .ticker: return "Тикер"
        }
    }

    var subtitle: String {
        switch self {
        case .card: return "Баланс"
        case .realEstate: return "Имущество"
        case .debt: return "Обязательство"
        case .crypto: return "Монета"
        case .credit: return "Платеж"
        case .ticker: return "1 позиция"
        }
    }

    var icon: String {
        switch self {
        case .card: return "creditcard.fill"
        case .realEstate: return "house.fill"
        case .debt: return "hand.raised.fill"
        case .crypto: return "bitcoinsign.circle.fill"
        case .credit: return "doc.text.fill"
        case .ticker: return "magnifyingglass"
        }
    }
}

struct QuickSetupProductDraft: Identifiable, Hashable {
    let id: UUID
    let type: QuickSetupProductType
    let name: String
    let amount: Double
    let currencyCode: String
    let symbol: String?
    let visualIcon: String?

    init(
        id: UUID = UUID(),
        type: QuickSetupProductType,
        name: String,
        amount: Double,
        currencyCode: String,
        symbol: String? = nil,
        visualIcon: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode
        self.symbol = symbol
        self.visualIcon = visualIcon
    }
}

struct QuickSetupSelection {
    let language: Language
    let primaryCurrencyCode: String
    let favoriteCurrencyCodes: [String]
    let selectedExpenseCategoryIDs: [String]
    let products: [QuickSetupProductDraft]
}

enum QuickSetupFlowMode {
    case onboarding
    case settings
}

struct QuickSetupExpenseCategoryPreset: Identifiable, Hashable {
    let id: String
    let displayName: String
    let icon: String
    let systemRaw: String?

    static let customPrefix = "custom:"

    static var all: [QuickSetupExpenseCategoryPreset] {
        all(for: Locale.current)
    }

    static func all(for locale: Locale) -> [QuickSetupExpenseCategoryPreset] {
        let languageCode = preferredLanguageCode(for: locale)
        var result: [QuickSetupExpenseCategoryPreset] = ExpenseCategory.allCases.map { category in
            QuickSetupExpenseCategoryPreset(
                id: category.rawValue,
                displayName: localizedSystemName(for: category, languageCode: languageCode),
                icon: category.icon,
                systemRaw: category.rawValue
            )
        }

        result.append(contentsOf: [
            QuickSetupExpenseCategoryPreset(
                id: "custom:travel",
                displayName: localizedCustomName(for: "custom:travel", languageCode: languageCode),
                icon: "✈️",
                systemRaw: nil
            ),
            QuickSetupExpenseCategoryPreset(
                id: "custom:home",
                displayName: localizedCustomName(for: "custom:home", languageCode: languageCode),
                icon: "🏠",
                systemRaw: nil
            ),
            QuickSetupExpenseCategoryPreset(
                id: "custom:pets",
                displayName: localizedCustomName(for: "custom:pets", languageCode: languageCode),
                icon: "🐾",
                systemRaw: nil
            ),
            QuickSetupExpenseCategoryPreset(
                id: "custom:sport",
                displayName: localizedCustomName(for: "custom:sport", languageCode: languageCode),
                icon: "🏋️",
                systemRaw: nil
            )
        ])

        return result
    }

    private static func preferredLanguageCode(for locale: Locale) -> String {
        if #available(iOS 16.0, *),
           let code = locale.language.languageCode?.identifier,
           !code.isEmpty {
            return code.lowercased()
        }

        if let code = locale.identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() {
            return String(code)
        }

        return "en"
    }

    private static func localizedSystemName(for category: ExpenseCategory, languageCode: String) -> String {
        switch (category, languageCode) {
        case (.groceries, "ru"): return "Продукты"
        case (.cafe, "ru"): return "Кафе"
        case (.transport, "ru"): return "Транспорт"
        case (.shopping, "ru"): return "Покупки"
        case (.entertainment, "ru"): return "Развлечения"
        case (.bills, "ru"): return "Счета"
        case (.health, "ru"): return "Здоровье"
        case (.education, "ru"): return "Образование"
        case (.other, "ru"): return "Другое"
        case (.groceries, _): return "Groceries"
        case (.cafe, _): return "Cafe"
        case (.transport, _): return "Transport"
        case (.shopping, _): return "Shopping"
        case (.entertainment, _): return "Entertainment"
        case (.bills, _): return "Bills"
        case (.health, _): return "Health"
        case (.education, _): return "Education"
        case (.other, _): return "Other"
        }
    }

    private static func localizedCustomName(for presetID: String, languageCode: String) -> String {
        switch (presetID, languageCode) {
        case ("custom:travel", "ru"): return "Путешествия"
        case ("custom:home", "ru"): return "Дом"
        case ("custom:pets", "ru"): return "Питомцы"
        case ("custom:sport", "ru"): return "Спорт"
        case ("custom:travel", _): return "Travel"
        case ("custom:home", _): return "Home"
        case ("custom:pets", _): return "Pets"
        case ("custom:sport", _): return "Sport"
        default: return presetID
        }
    }
}
