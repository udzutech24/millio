import Foundation

enum QuickSetupStep: Int, CaseIterable, Identifiable {
    case localeAndCurrencies
    case expenseCategories
    case products
    case summary

    var id: Int { rawValue }

    var title: String {
        title(for: Locale.current)
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .localeAndCurrencies:
            return QuickSetupLocalization.text(locale: locale, ru: "Язык и валюты", en: "Language and currencies")
        case .expenseCategories:
            return QuickSetupLocalization.text(locale: locale, ru: "Категории", en: "Categories")
        case .products:
            return QuickSetupLocalization.text(locale: locale, ru: "Продукты", en: "Products")
        case .summary:
            return QuickSetupLocalization.text(locale: locale, ru: "Хранение данных", en: "Data storage")
        }
    }

    var subtitle: String {
        subtitle(for: Locale.current)
    }

    func subtitle(for locale: Locale) -> String {
        switch self {
        case .localeAndCurrencies:
            return QuickSetupLocalization.text(locale: locale, ru: "Выберите язык и валюты", en: "Choose language and currencies")
        case .expenseCategories:
            return QuickSetupLocalization.text(locale: locale, ru: "Оставьте нужные категории", en: "Keep only needed categories")
        case .products:
            return QuickSetupLocalization.text(locale: locale, ru: "Добавьте счета и активы", en: "Add accounts and assets")
        case .summary:
            return QuickSetupLocalization.text(locale: locale, ru: "Выберите режим хранения и backup", en: "Select storage and backup mode")
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
        title(for: Locale.current)
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .card: return QuickSetupLocalization.text(locale: locale, ru: "Карта", en: "Card")
        case .realEstate: return QuickSetupLocalization.text(locale: locale, ru: "Недвиж.", en: "Property")
        case .debt: return QuickSetupLocalization.text(locale: locale, ru: "Долг", en: "Debt")
        case .crypto: return QuickSetupLocalization.text(locale: locale, ru: "Крипто", en: "Crypto")
        case .credit: return QuickSetupLocalization.text(locale: locale, ru: "Кредит", en: "Credit")
        case .ticker: return QuickSetupLocalization.text(locale: locale, ru: "Тикер", en: "Ticker")
        }
    }

    var subtitle: String {
        subtitle(for: Locale.current)
    }

    func subtitle(for locale: Locale) -> String {
        switch self {
        case .card: return QuickSetupLocalization.text(locale: locale, ru: "Баланс", en: "Balance")
        case .realEstate: return QuickSetupLocalization.text(locale: locale, ru: "Имущество", en: "Asset")
        case .debt: return QuickSetupLocalization.text(locale: locale, ru: "Обязательство", en: "Liability")
        case .crypto: return QuickSetupLocalization.text(locale: locale, ru: "Монета", en: "Coin")
        case .credit: return QuickSetupLocalization.text(locale: locale, ru: "Платеж", en: "Payment")
        case .ticker: return QuickSetupLocalization.text(locale: locale, ru: "1 позиция", en: "1 position")
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
        title(for: Locale.current)
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .localOnly:
            return QuickSetupLocalization.text(locale: locale, ru: "Локальный контур", en: "Local mode")
        case .cloudBackup:
            return QuickSetupLocalization.text(locale: locale, ru: "Локально + iCloud", en: "Local + iCloud")
        }
    }

    var subtitle: String {
        subtitle(for: Locale.current)
    }

    func subtitle(for locale: Locale) -> String {
        switch self {
        case .localOnly:
            return QuickSetupLocalization.text(locale: locale, ru: "Данные хранятся только на устройстве в SwiftData, выгрузка отключена", en: "Data stays on device in SwiftData, upload is disabled")
        case .cloudBackup:
            return QuickSetupLocalization.text(locale: locale, ru: "Снимки хранятся в Private CloudKit вашего Apple ID", en: "Snapshots are stored in your Apple ID Private CloudKit")
        }
    }

    var details: String {
        details(for: Locale.current)
    }

    func details(for locale: Locale) -> String {
        switch self {
        case .localOnly:
            return QuickSetupLocalization.text(locale: locale, ru: "Выгрузку можно включить позже: Профиль -> Backup", en: "Upload can be enabled later in Profile -> Backup")
        case .cloudBackup:
            return QuickSetupLocalization.text(locale: locale, ru: "Шифрование: AES-GCM с ключом устройства или парольной фразой", en: "Encryption: AES-GCM with device key or passphrase")
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
