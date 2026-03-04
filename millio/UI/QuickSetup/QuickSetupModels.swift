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
        var result: [QuickSetupExpenseCategoryPreset] = ExpenseCategory.allCases.map { category in
            QuickSetupExpenseCategoryPreset(
                id: category.rawValue,
                displayName: category.displayName,
                icon: category.icon,
                systemRaw: category.rawValue
            )
        }

        result.append(contentsOf: [
            QuickSetupExpenseCategoryPreset(id: "custom:travel", displayName: "Путешествия", icon: "✈️", systemRaw: nil),
            QuickSetupExpenseCategoryPreset(id: "custom:home", displayName: "Дом", icon: "🏠", systemRaw: nil),
            QuickSetupExpenseCategoryPreset(id: "custom:pets", displayName: "Питомцы", icon: "🐾", systemRaw: nil),
            QuickSetupExpenseCategoryPreset(id: "custom:sport", displayName: "Спорт", icon: "🏋️", systemRaw: nil)
        ])

        return result
    }
}
