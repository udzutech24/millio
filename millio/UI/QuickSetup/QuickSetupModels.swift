import Foundation

enum QuickSetupStep: Int, CaseIterable, Identifiable {
    case localeAndCurrencies
    case expenseCategories
    case products
    case summary

    var id: Int { rawValue }

    var title: String {
        title(for: AppLocalization.currentAppLocale)
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .localeAndCurrencies:
            return QuickSetupLocalization.tr("quick_setup.step.locale_and_currencies.title", locale: locale)
        case .expenseCategories:
            return QuickSetupLocalization.tr("quick_setup.step.expense_categories.title", locale: locale)
        case .products:
            return QuickSetupLocalization.tr("quick_setup.step.products.title", locale: locale)
        case .summary:
            return QuickSetupLocalization.tr("quick_setup.step.summary.title", locale: locale)
        }
    }

    var subtitle: String {
        subtitle(for: AppLocalization.currentAppLocale)
    }

    func subtitle(for locale: Locale) -> String {
        switch self {
        case .localeAndCurrencies:
            return QuickSetupLocalization.tr("quick_setup.step.locale_and_currencies.subtitle", locale: locale)
        case .expenseCategories:
            return QuickSetupLocalization.tr("quick_setup.step.expense_categories.subtitle", locale: locale)
        case .products:
            return QuickSetupLocalization.tr("quick_setup.step.products.subtitle", locale: locale)
        case .summary:
            return QuickSetupLocalization.tr("quick_setup.step.summary.subtitle", locale: locale)
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
        title(for: AppLocalization.currentAppLocale)
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .card: return QuickSetupLocalization.tr("quick_setup.product_type.card.title", locale: locale)
        case .realEstate: return QuickSetupLocalization.tr("quick_setup.product_type.real_estate.title", locale: locale)
        case .debt: return QuickSetupLocalization.tr("quick_setup.product_type.debt.title", locale: locale)
        case .crypto: return QuickSetupLocalization.tr("quick_setup.product_type.crypto.title", locale: locale)
        case .credit: return QuickSetupLocalization.tr("quick_setup.product_type.credit.title", locale: locale)
        case .ticker: return QuickSetupLocalization.tr("quick_setup.product_type.ticker.title", locale: locale)
        }
    }

    var subtitle: String {
        subtitle(for: AppLocalization.currentAppLocale)
    }

    func subtitle(for locale: Locale) -> String {
        switch self {
        case .card: return QuickSetupLocalization.tr("quick_setup.product_type.card.subtitle", locale: locale)
        case .realEstate: return QuickSetupLocalization.tr("quick_setup.product_type.real_estate.subtitle", locale: locale)
        case .debt: return QuickSetupLocalization.tr("quick_setup.product_type.debt.subtitle", locale: locale)
        case .crypto: return QuickSetupLocalization.tr("quick_setup.product_type.crypto.subtitle", locale: locale)
        case .credit: return QuickSetupLocalization.tr("quick_setup.product_type.credit.subtitle", locale: locale)
        case .ticker: return QuickSetupLocalization.tr("quick_setup.product_type.ticker.subtitle", locale: locale)
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

    var recommendedGroupTemplate: FinanceGroupNameTemplate {
        switch self {
        case .card:
            return .debitCards
        case .realEstate, .crypto:
            return .myRealEstate
        case .debt, .credit:
            return .credits
        case .ticker:
            return .stocks
        }
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
        title(for: AppLocalization.currentAppLocale)
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
        QuickSetupGroupPreset(template: .myRealEstate, colorHex: "#BE123C", icon: "shippingbox.fill"),
        QuickSetupGroupPreset(template: .credits, colorHex: "#B45309", icon: "doc.text.fill"),
        QuickSetupGroupPreset(template: .stocks, colorHex: "#15803D", icon: "chart.line.uptrend.xyaxis"),
        QuickSetupGroupPreset(template: .foreignCards, colorHex: "#7C3AED", icon: "globe.europe.africa.fill"),
        QuickSetupGroupPreset(template: .deposits, colorHex: "#0369A1", icon: "banknote.fill")
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
        title(for: AppLocalization.currentAppLocale)
    }

    func title(for locale: Locale) -> String {
        switch self {
        case .localOnly:
            return QuickSetupLocalization.tr("quick_setup.backup.local_only.title", locale: locale)
        case .cloudBackup:
            return QuickSetupLocalization.tr("quick_setup.backup.cloud_backup.title", locale: locale)
        }
    }

    var subtitle: String {
        subtitle(for: AppLocalization.currentAppLocale)
    }

    func subtitle(for locale: Locale) -> String {
        switch self {
        case .localOnly:
            return QuickSetupLocalization.tr("quick_setup.backup.local_only.subtitle", locale: locale)
        case .cloudBackup:
            return QuickSetupLocalization.tr("quick_setup.backup.cloud_backup.subtitle", locale: locale)
        }
    }

    var details: String {
        details(for: AppLocalization.currentAppLocale)
    }

    func details(for locale: Locale) -> String {
        switch self {
        case .localOnly:
            return QuickSetupLocalization.tr("quick_setup.backup.local_only.details", locale: locale)
        case .cloudBackup:
            return QuickSetupLocalization.tr("quick_setup.backup.cloud_backup.details", locale: locale)
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
        all(for: AppLocalization.currentAppLocale)
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
