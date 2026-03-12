import Foundation
import Combine

enum QuickSetupProductFlowPolicy {
    static func shouldAutoOpenMarketSearch(previousType: QuickSetupProductType, newType: QuickSetupProductType) -> Bool {
        previousType != newType && newType.isMarketTracked
    }
}

struct QuickSetupSystemContext {
    let preferredLanguageIdentifiers: [String]
    let locale: Locale

    static var current: QuickSetupSystemContext {
        QuickSetupSystemContext(
            preferredLanguageIdentifiers: Locale.preferredLanguages,
            locale: Locale.autoupdatingCurrent
        )
    }

    var hasRussianSystemLanguage: Bool {
        preferredLanguageIdentifiers.contains { identifier in
            normalizedLanguageCode(from: identifier) == Language.russian.rawValue
        } || normalizedLanguageCode(from: locale.identifier) == Language.russian.rawValue
    }

    var quickSetupAvailableLanguages: [Language] {
        hasRussianSystemLanguage ? [.system, .english, .russian] : [.system, .english]
    }

    var recommendedCurrencyCodes: [String] {
        if hasRussianSystemLanguage {
            return ["RUB", "USD", "CNY", "EUR", "TRY"]
        }

        let defaults = uniqueCurrencyCodes([
            fallbackCurrencyCodeForPrimaryLanguage,
            systemCurrencyCode,
            "USD",
            "EUR",
            "CNY",
            "GBP",
            "JPY",
            "CHF",
            "CAD",
            "AUD"
        ])

        return defaults.filter { $0 != "RUB" }
    }

    func recommendedPrimaryCurrency(fallback fallbackCode: String) -> String {
        let normalizedFallback = normalizeCurrencyCode(fallbackCode)
        return sanitizePrimaryCurrency(recommendedCurrencyCodes.first ?? normalizedFallback, fallback: normalizedFallback)
    }

    func recommendedFavoriteCurrencies(primaryCode: String, maxCount: Int) -> [String] {
        let normalizedPrimary = normalizeCurrencyCode(primaryCode)
        if !hasRussianSystemLanguage {
            return Array(
                uniqueCurrencyCodes(["USD", "EUR", "CNY"])
                    .filter { $0 != normalizedPrimary }
                    .prefix(maxCount)
            )
        }

        return Array(
            recommendedCurrencyCodes
                .filter { $0 != normalizedPrimary }
                .prefix(maxCount)
        )
    }

    func sanitizePrimaryCurrency(_ candidateCode: String, fallback fallbackCode: String) -> String {
        let normalizedCandidate = normalizeCurrencyCode(candidateCode)
        let normalizedFallback = normalizeCurrencyCode(fallbackCode)
        let firstRecommended = recommendedCurrencyCodes.first ?? normalizedFallback

        guard !normalizedCandidate.isEmpty else {
            return firstRecommended
        }
        if !hasRussianSystemLanguage, normalizedCandidate == "RUB" {
            return firstRecommended == "RUB" ? "USD" : firstRecommended
        }
        return normalizedCandidate
    }

    func sanitizeFavoriteCurrencies(
        _ rawCodes: [String],
        primaryCode: String,
        maxCount: Int
    ) -> [String] {
        let normalizedPrimary = normalizeCurrencyCode(primaryCode)
        let fallback = recommendedFavoriteCurrencies(primaryCode: normalizedPrimary, maxCount: maxCount)
        let allowedCodes = Set(recommendedCurrencyCodes)

        let filtered = uniqueCurrencyCodes(rawCodes)
            .filter { code in
                code != normalizedPrimary
                    && code != "RUB"
                    && (hasRussianSystemLanguage || allowedCodes.contains(code))
            }

        if filtered.isEmpty {
            return Array(fallback.prefix(maxCount))
        }

        return Array(filtered.prefix(maxCount))
    }

    private var systemCurrencyCode: String? {
        // Project target is iOS 16+, so prefer the non-deprecated API.
        locale.currency?.identifier.uppercased()
    }

    private var fallbackCurrencyCodeForPrimaryLanguage: String? {
        switch normalizedLanguageCode(from: preferredLanguageIdentifiers.first ?? locale.identifier) {
        case "en":
            return "USD"
        case "tr":
            return "TRY"
        case "zh":
            return "CNY"
        case "ja":
            return "JPY"
        case "de", "fr", "es", "it", "pt", "nl":
            return "EUR"
        default:
            return nil
        }
    }

    private func normalizedLanguageCode(from identifier: String) -> String {
        String(
            identifier
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first?
                .lowercased() ?? ""
        )
    }

    private func normalizeCurrencyCode(_ code: String?) -> String {
        code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    }

    private func uniqueCurrencyCodes(_ codes: [String?]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for code in codes {
            let normalized = normalizeCurrencyCode(code)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }
}

@MainActor
final class QuickSetupViewModel: ObservableObject {
    static let recommendedExpenseCategoryIDs: [String] = [
        ExpenseCategory.groceries.rawValue,
        ExpenseCategory.transport.rawValue,
        ExpenseCategory.shopping.rawValue,
        ExpenseCategory.cafe.rawValue,
        ExpenseCategory.bills.rawValue,
        ExpenseCategory.health.rawValue,
        ExpenseCategory.education.rawValue,
        ExpenseCategory.other.rawValue,
        "custom:travel",
        "custom:home"
    ]

    @Published var currentStep: QuickSetupStep = .localeAndCurrencies
    @Published var selectedLanguage: Language
    @Published var primaryCurrencyCode: String {
        didSet {
            removePrimaryFromFavorites()
        }
    }
    @Published var favoriteCurrencyCodes: [String]
    @Published var selectedExpenseCategoryIDs: Set<String>
    @Published var productTypeForCreation: QuickSetupProductType = .card
    @Published var productNameInput: String = ""
    @Published var productSymbolInput: String = ""
    @Published var productAmountInput: String = ""
    @Published var productQuantityInput: String = ""
    @Published var productPurchasePriceInput: String = ""
    @Published var productCurrentPriceInput: String = ""
    @Published private(set) var productMarketExchange: String?
    @Published private(set) var productMarketCurrencyCode: String?
    @Published private(set) var productLatestUnitPrice: Double?
    @Published private(set) var productLastPriceUpdatedAt: Date?
    @Published private(set) var isRefreshingProductQuote = false
    @Published private(set) var productMarketError: String?
    @Published var products: [QuickSetupProductDraft] = []
    @Published var backupPreference: QuickSetupBackupPreference
    @Published private(set) var lastAddDraftError: String?

    private let isProUser: Bool
    private let systemContext: QuickSetupSystemContext
    private let marketDataClient: MarketDataClientProtocol
    private let defaults: UserDefaults

    static let maxFavoriteCurrencies = 4

    init(
        appState: AppState,
        systemContext: QuickSetupSystemContext = .current,
        marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared,
        defaults: UserDefaults = .standard
    ) {
        isProUser = appState.isPro
        self.systemContext = systemContext
        self.marketDataClient = marketDataClient
        self.defaults = defaults
        selectedLanguage = appState.selectedLanguage
        let recommendedPrimary = systemContext.recommendedPrimaryCurrency(fallback: appState.primaryCurrencyCode)
        let hasStoredPrimaryCurrency = defaults.object(forKey: "primaryCurrencyCode") != nil
        let initialPrimaryCandidate = hasStoredPrimaryCurrency ? appState.primaryCurrencyCode : recommendedPrimary
        let initialPrimaryCurrency = systemContext.sanitizePrimaryCurrency(
            initialPrimaryCandidate,
            fallback: recommendedPrimary
        )
        primaryCurrencyCode = initialPrimaryCurrency

        let hasStoredFavoriteCurrencies = defaults.object(forKey: "favoriteCurrencyCodes") != nil
        let initialFavorites = hasStoredFavoriteCurrencies
            ? Array(SettingsManager.shared.favoriteCurrencyCodes.prefix(Self.maxFavoriteCurrencies))
            : systemContext.recommendedFavoriteCurrencies(
                primaryCode: initialPrimaryCurrency,
                maxCount: Self.maxFavoriteCurrencies
            )
        favoriteCurrencyCodes = systemContext.sanitizeFavoriteCurrencies(
            initialFavorites,
            primaryCode: initialPrimaryCurrency,
            maxCount: Self.maxFavoriteCurrencies
        )
        backupPreference = appState.isBackupEnabled ? .cloudBackup : .localOnly

        let storedCategories = SettingsManager.shared.quickSetupExpenseCategoryIDs
        if storedCategories.isEmpty {
            selectedExpenseCategoryIDs = Set(Self.recommendedExpenseCategoryIDs)
        } else {
            selectedExpenseCategoryIDs = Set(storedCategories)
        }
    }

    var availableLanguages: [Language] {
        systemContext.quickSetupAvailableLanguages
    }

    var recommendedCurrencyCodes: [String] {
        systemContext.recommendedCurrencyCodes
    }

    var isMarketProductDraft: Bool {
        productTypeForCreation.isMarketTracked
    }

    var productAmountFieldTitle: String {
        let locale = selectedLanguage.locale ?? Locale.current
        switch productTypeForCreation {
        case .card:
            return QuickSetupLocalization.text(locale: locale, ru: "Баланс в \(primaryCurrencyCode)", en: "Balance in \(primaryCurrencyCode)")
        case .realEstate:
            return QuickSetupLocalization.text(locale: locale, ru: "Стоимость в \(primaryCurrencyCode)", en: "Value in \(primaryCurrencyCode)")
        case .debt:
            return QuickSetupLocalization.text(locale: locale, ru: "Сумма долга в \(primaryCurrencyCode)", en: "Debt amount in \(primaryCurrencyCode)")
        case .credit:
            return QuickSetupLocalization.text(locale: locale, ru: "Остаток долга в \(primaryCurrencyCode)", en: "Outstanding debt in \(primaryCurrencyCode)")
        case .crypto, .ticker:
            return QuickSetupLocalization.text(locale: locale, ru: "Количество", en: "Quantity")
        }
    }

    var productPurchasePriceTitle: String {
        let locale = selectedLanguage.locale ?? Locale.current
        return productTypeForCreation == .crypto
            ? QuickSetupLocalization.text(locale: locale, ru: "Цена покупки за монету", en: "Buy price per coin")
            : QuickSetupLocalization.text(locale: locale, ru: "Цена покупки за 1 шт.", en: "Buy price per share")
    }

    var productMarketSearchTitle: String {
        let locale = selectedLanguage.locale ?? Locale.current
        return productTypeForCreation == .crypto
            ? QuickSetupLocalization.text(locale: locale, ru: "Найти пару", en: "Find pair")
            : QuickSetupLocalization.text(locale: locale, ru: "Найти тикер", en: "Find ticker")
    }

    var productResolvedCurrencyCode: String {
        let preferredCode = productMarketCurrencyCode ?? primaryCurrencyCode
        let normalized = preferredCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? SettingsManager.defaultPrimaryCurrencyCode : normalized
    }

    var productPositionTotal: Double? {
        guard let quantity = parsedDecimal(productQuantityInput), quantity > 0 else { return nil }
        if let currentUnitPrice = resolvedCurrentUnitPrice, currentUnitPrice > 0 {
            return quantity * currentUnitPrice
        }
        if let purchaseUnitPrice = parsedDecimal(productPurchasePriceInput), purchaseUnitPrice > 0 {
            return quantity * purchaseUnitPrice
        }
        return nil
    }

    var productPositionGrowthAbsolute: Double? {
        guard
            let quantity = parsedDecimal(productQuantityInput),
            quantity > 0,
            let currentUnitPrice = resolvedCurrentUnitPrice,
            currentUnitPrice > 0,
            let purchaseUnitPrice = parsedDecimal(productPurchasePriceInput),
            purchaseUnitPrice > 0
        else {
            return nil
        }

        return quantity * (currentUnitPrice - purchaseUnitPrice)
    }

    var progress: Double {
        Double(currentStep.rawValue + 1) / Double(QuickSetupStep.allCases.count)
    }

    var canContinue: Bool {
        switch currentStep {
        case .localeAndCurrencies:
            return
                !primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !favoriteCurrencyCodes.isEmpty
        case .expenseCategories:
            return !selectedExpenseCategoryIDs.isEmpty
        case .products:
            return true
        case .summary:
            return true
        }
    }

    var continueTitle: String {
        let locale = selectedLanguage.locale ?? Locale.current
        switch currentStep {
        case .summary:
            return QuickSetupLocalization.text(locale: locale, ru: "Завершить", en: "Finish")
        default:
            return QuickSetupLocalization.text(locale: locale, ru: "Продолжить", en: "Continue")
        }
    }

    func makeSelection() -> QuickSetupSelection {
        let normalizedPrimary = primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedFavorites = SettingsManager
            .normalizeFavoriteCurrencyCodes(favoriteCurrencyCodes, primaryCode: normalizedPrimary)

        return QuickSetupSelection(
            language: selectedLanguage,
            primaryCurrencyCode: normalizedPrimary,
            favoriteCurrencyCodes: Array(normalizedFavorites.prefix(Self.maxFavoriteCurrencies)),
            selectedExpenseCategoryIDs: Array(selectedExpenseCategoryIDs),
            products: products,
            backupPreference: backupPreference
        )
    }

    func goNextStep() {
        guard canContinue else { return }
        if let next = QuickSetupStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    func goBackStep() {
        if let prev = QuickSetupStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
    }

    func toggleFavoriteCurrency(_ rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        guard code != primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else { return }

        if let index = favoriteCurrencyCodes.firstIndex(of: code) {
            favoriteCurrencyCodes.remove(at: index)
            return
        }

        guard favoriteCurrencyCodes.count < Self.maxFavoriteCurrencies else { return }
        favoriteCurrencyCodes.insert(code, at: 0)
    }

    private func removePrimaryFromFavorites() {
        let normalizedPrimary = primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        favoriteCurrencyCodes.removeAll { code in
            code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedPrimary
        }
    }

    func toggleExpenseCategory(raw: String) {
        if selectedExpenseCategoryIDs.contains(raw) {
            selectedExpenseCategoryIDs.remove(raw)
        } else {
            selectedExpenseCategoryIDs.insert(raw)
        }
    }

    func applyRecommendedExpenseCategories() {
        selectedExpenseCategoryIDs = Set(Self.recommendedExpenseCategoryIDs)
    }

    func clearExpenseCategories() {
        selectedExpenseCategoryIDs.removeAll()
    }

    func selectProductType(_ type: QuickSetupProductType) {
        productTypeForCreation = type
        resetDraftInputs(keepingTypeSpecificData: false)
    }

    func applySelectedMarketSymbol(_ symbol: TwelveDataSymbol) {
        productSymbolInput = symbol.symbol.uppercased()
        productMarketExchange = symbol.exchange
        productMarketCurrencyCode = symbol.currency?.uppercased()
        productMarketError = nil
    }

    func refreshSelectedMarketQuote(forceRefresh: Bool) async {
        let symbol = productSymbolInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !symbol.isEmpty else { return }

        isRefreshingProductQuote = true
        productMarketError = nil
        defer { isRefreshingProductQuote = false }

        do {
            let latestPrice = try await marketDataClient.latestPrice(symbol: symbol, forceRefresh: forceRefresh)
            productLatestUnitPrice = latestPrice
            productLastPriceUpdatedAt = latestPrice == nil ? nil : Date()
        } catch {
            productMarketError = error.localizedDescription
        }
    }

    @discardableResult
    func addDraftProduct() -> Bool {
        lastAddDraftError = nil
        let trimmedName = productNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = productSymbolInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let resolvedName: String
        let amount: Double
        let marketSnapshot: QuickSetupProductMarketSnapshot?

        if productTypeForCreation.isMarketTracked {
            guard !trimmedSymbol.isEmpty else {
                lastAddDraftError = String(localized: "quick_setup.error.enter_ticker")
                return false
            }
            guard let quantity = parsedDecimal(productQuantityInput), quantity > 0 else {
                let locale = selectedLanguage.locale ?? Locale.current
                lastAddDraftError = QuickSetupLocalization.text(locale: locale, ru: "Укажи количество позиции", en: "Enter position quantity")
                return false
            }
            let purchaseUnitPrice: Double
            if productTypeForCreation == .crypto {
                purchaseUnitPrice = max(0, parsedDecimal(productPurchasePriceInput) ?? 0)
            } else {
                guard let parsedPurchaseUnitPrice = parsedDecimal(productPurchasePriceInput), parsedPurchaseUnitPrice > 0 else {
                    let locale = selectedLanguage.locale ?? Locale.current
                    lastAddDraftError = QuickSetupLocalization.text(locale: locale, ru: "Укажи цену покупки", en: "Enter buy price")
                    return false
                }
                purchaseUnitPrice = parsedPurchaseUnitPrice
            }
            let currentTickerDraftCount = products.reduce(into: 0) { partialResult, item in
                if item.type.isMarketTracked {
                    partialResult += 1
                }
            }
            if !EntitlementPolicy.canAddTrackedTicker(
                isPro: isProUser,
                currentTrackedTickers: currentTickerDraftCount
            ) {
                lastAddDraftError = String(
                    format: String(localized: "monetization.ticker.limit.short_format"),
                    EntitlementPolicy.freeTrackedTickerLimit
                )
                return false
            }

            let manualCurrentUnitPrice = parsedDecimal(productCurrentPriceInput)
            let effectivePurchaseUnitPrice = purchaseUnitPrice > 0 ? purchaseUnitPrice : (resolvedCurrentUnitPrice ?? 0)
            let currentUnitPrice = resolvedCurrentUnitPrice ?? effectivePurchaseUnitPrice
            let resolvedCurrency = productResolvedCurrencyCode
            resolvedName = trimmedSymbol
            amount = quantity * currentUnitPrice
            marketSnapshot = QuickSetupProductMarketSnapshot(
                symbol: trimmedSymbol,
                exchange: productMarketExchange,
                currencyCode: resolvedCurrency,
                quantity: quantity,
                purchaseUnitPrice: effectivePurchaseUnitPrice,
                currentUnitPrice: productLatestUnitPrice ?? manualCurrentUnitPrice,
                priceUpdatedAt: productLastPriceUpdatedAt,
                providerRaw: productLatestUnitPrice == nil ? nil : "market-backend"
            )
        } else {
            guard !trimmedName.isEmpty else {
                lastAddDraftError = String(localized: "quick_setup.error.enter_name")
                return false
            }
            resolvedName = trimmedName
            amount = max(0, parsedDecimal(productAmountInput) ?? 0)
            marketSnapshot = nil
        }

        let normalizedCurrency = productTypeForCreation.isMarketTracked
            ? productResolvedCurrencyCode
            : primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        products.append(
            QuickSetupProductDraft(
                type: productTypeForCreation,
                name: resolvedName,
                amount: amount,
                currencyCode: normalizedCurrency.isEmpty ? SettingsManager.defaultPrimaryCurrencyCode : normalizedCurrency,
                marketSnapshot: marketSnapshot,
                visualIcon: productTypeForCreation.icon
            )
        )

        resetDraftInputs(keepingTypeSpecificData: false)
        return true
    }

    func removeProduct(id: UUID) {
        products.removeAll { $0.id == id }
    }

    private func resetDraftInputs(keepingTypeSpecificData: Bool) {
        productNameInput = ""
        productAmountInput = ""
        productQuantityInput = ""
        productPurchasePriceInput = ""
        productCurrentPriceInput = ""

        guard !keepingTypeSpecificData else { return }

        productSymbolInput = ""
        productMarketExchange = nil
        productMarketCurrencyCode = nil
        productLatestUnitPrice = nil
        productLastPriceUpdatedAt = nil
        productMarketError = nil
    }

    private func parsedDecimal(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var resolvedCurrentUnitPrice: Double? {
        if let latest = productLatestUnitPrice, latest > 0 {
            return latest
        }
        if let manual = parsedDecimal(productCurrentPriceInput), manual > 0 {
            return manual
        }
        return nil
    }
}
