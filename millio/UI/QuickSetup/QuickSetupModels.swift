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
            return "Безопасность"
        }
    }

    var subtitle: String {
        switch self {
        case .localeAndCurrencies:
            return "Выберите язык приложения и основные валюты."
        case .expenseCategories:
            return "Оставьте только те категории, которые нужны с первого дня."
        case .products:
            return "Добавьте счета и активы, если хотите увидеть их сразу в Финансах."
        case .summary:
            return "Выберите, как хранить данные и резервные копии."
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

    var isMarketTracked: Bool {
        self == .ticker || self == .crypto
    }
}

struct QuickSetupProductMarketSnapshot: Hashable {
    let symbol: String
    let exchange: String?
    let currencyCode: String
    let quantity: Double
    let purchaseUnitPrice: Double
    let currentUnitPrice: Double?
    let priceUpdatedAt: Date?
    let providerRaw: String?
}

struct QuickSetupProductDraft: Identifiable, Hashable {
    let id: UUID
    let type: QuickSetupProductType
    let name: String
    let amount: Double
    let currencyCode: String
    let marketSnapshot: QuickSetupProductMarketSnapshot?
    let visualIcon: String?

    var symbol: String? {
        marketSnapshot?.symbol
    }

    init(
        id: UUID = UUID(),
        type: QuickSetupProductType,
        name: String,
        amount: Double,
        currencyCode: String,
        marketSnapshot: QuickSetupProductMarketSnapshot? = nil,
        visualIcon: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode
        self.marketSnapshot = marketSnapshot
        self.visualIcon = visualIcon
    }
}

struct QuickSetupSelection {
    let language: Language
    let primaryCurrencyCode: String
    let favoriteCurrencyCodes: [String]
    let selectedExpenseCategoryIDs: [String]
    let products: [QuickSetupProductDraft]
    let backupPreference: QuickSetupBackupPreference
}

enum QuickSetupBackupPreference: String, CaseIterable, Identifiable {
    case localOnly
    case cloudBackup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localOnly:
            return "Только на устройстве"
        case .cloudBackup:
            return "Выгружать в iCloud"
        }
    }

    var subtitle: String {
        switch self {
        case .localOnly:
            return "Данные останутся локально в SwiftData. Выгрузка выключена."
        case .cloudBackup:
            return "Снимки хранятся в Private CloudKit вашего Apple ID."
        }
    }

    var details: String {
        switch self {
        case .localOnly:
            return "В любой момент можно включить выгрузку в Профиль -> Backup."
        case .cloudBackup:
            return "Шифрование backup: AES-GCM (ключ устройства) или парольная фраза в Backup."
        }
    }

    var isBackupEnabled: Bool {
        switch self {
        case .localOnly:
            return false
        case .cloudBackup:
            return true
        }
    }
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
