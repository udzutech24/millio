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
    let groupDraftID: UUID?
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
        groupDraftID: UUID? = nil,
        marketSnapshot: QuickSetupProductMarketSnapshot? = nil,
        visualIcon: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode
        self.groupDraftID = groupDraftID
        self.marketSnapshot = marketSnapshot
        self.visualIcon = visualIcon
    }
}

struct QuickSetupGroupDraft: Identifiable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String
    let icon: String
    let template: FinanceGroupNameTemplate?

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        icon: String,
        template: FinanceGroupNameTemplate? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.template = template
    }
}

struct QuickSetupGroupPreset: Identifiable, Hashable {
    let template: FinanceGroupNameTemplate
    let colorHex: String
    let icon: String

    var id: String { template.rawValue }

    var title: String {
        title(for: Locale.current)
    }

    func title(for locale: Locale) -> String {
        AppLocalization.string(template.localizationKey, locale: locale, fallback: template.title)
    }

    func draft(for locale: Locale) -> QuickSetupGroupDraft {
        QuickSetupGroupDraft(
            name: title(for: locale),
            colorHex: colorHex,
            icon: icon,
            template: template
        )
    }

    static let all: [QuickSetupGroupPreset] = [
        QuickSetupGroupPreset(template: .debitCards, colorHex: "#1D4ED8", icon: "creditcard.fill"),
        QuickSetupGroupPreset(template: .foreignCards, colorHex: "#7C3AED", icon: "globe.europe.africa.fill"),
        QuickSetupGroupPreset(template: .credits, colorHex: "#B45309", icon: "doc.text.fill"),
        QuickSetupGroupPreset(template: .stocks, colorHex: "#15803D", icon: "chart.line.uptrend.xyaxis"),
        QuickSetupGroupPreset(template: .deposits, colorHex: "#0369A1", icon: "banknote.fill"),
        QuickSetupGroupPreset(template: .myRealEstate, colorHex: "#BE123C", icon: "shippingbox.fill")
    ]
}

struct QuickSetupSelection {
    let language: Language
    let primaryCurrencyCode: String
    let favoriteCurrencyCodes: [String]
    let selectedExpenseCategoryIDs: [String]
    let groups: [QuickSetupGroupDraft]
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
        ExpenseCategory.allCases.map { category in
            let metadata = ExpenseCategoryCatalog.metadata(for: category)
            return QuickSetupExpenseCategoryPreset(
                id: category.rawValue,
                displayName: metadata.localizedDisplayName(locale: locale),
                icon: metadata.icon,
                systemRaw: category.rawValue
            )
        }
    }
}
