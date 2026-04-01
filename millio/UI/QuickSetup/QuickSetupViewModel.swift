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

    var hasChineseSystemLanguage: Bool {
        preferredLanguageIdentifiers.contains { identifier in
            normalizedLanguageCode(from: identifier) == "zh"
        } || normalizedLanguageCode(from: locale.identifier) == "zh"
    }

    var quickSetupAvailableLanguages: [Language] {
        LocalizationSupport.quickSetupSelectableLanguages(
            preferredLanguageIdentifiers: preferredLanguageIdentifiers,
            locale: locale
        )
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
    enum FavoriteCurrencyToggleResult: Equatable {
        case ignored
        case added
        case removed
    }

    static let recommendedExpenseCategoryIDs: [String] = [
        ExpenseCategory.groceries.rawValue,
        ExpenseCategory.dining.rawValue,
        ExpenseCategory.transport.rawValue,
        ExpenseCategory.housing.rawValue,
        ExpenseCategory.utilities.rawValue,
        ExpenseCategory.telecom.rawValue,
        ExpenseCategory.shopping.rawValue,
        ExpenseCategory.health.rawValue,
        ExpenseCategory.education.rawValue,
        ExpenseCategory.other.rawValue
    ]

    static let allExpenseCategoryIDs: [String] = ExpenseCategory.allCases.map(\.rawValue)

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
    @Published private(set) var hasExplicitlySelectedProductType = false
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
    @Published var groups: [QuickSetupGroupDraft] = []
    @Published var selectedGroupDraftID: UUID?
    @Published var products: [QuickSetupProductDraft] = []
    @Published var backupPreference: QuickSetupBackupPreference {
        didSet {
            if backupPreference != initialBackupPreference {
                hasCustomizedBackupPreference = true
            }
        }
    }
    @Published private(set) var lastAddDraftError: String?

    private let isProUser: Bool
    private let systemContext: QuickSetupSystemContext
    private let marketDataClient: MarketDataClientProtocol
    private let defaults: UserDefaults
    private let initialBackupPreference: QuickSetupBackupPreference
    private var hasCustomizedBackupPreference = false

    static let maxFavoriteCurrencies = 4

    var presentationLocale: Locale {
        if let selectedLocale = selectedLanguage.locale {
            return selectedLocale
        }

        if let preferredLanguageIdentifier = systemContext.preferredLanguageIdentifiers.first {
            return Locale(identifier: preferredLanguageIdentifier)
        }

        return systemContext.locale
    }

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
        initialBackupPreference = appState.isBackupEnabled ? .cloudBackup : .localOnly
        backupPreference = .cloudBackup

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

    var availableProductTypes: [QuickSetupProductType] {
        QuickSetupProductType.allCases.filter { type in
            type != .crypto || EntitlementPolicy.canUseQuickSetupCrypto(isPro: isProUser)
        }
    }

    var recommendedCurrencyCodes: [String] {
        systemContext.recommendedCurrencyCodes
    }

    var isMarketProductDraft: Bool {
        productTypeForCreation.isMarketTracked
    }

    var productAmountFieldTitle: String {
        let locale = presentationLocale
        switch productTypeForCreation {
        case .card:
            return QuickSetupLocalization.format("quick_setup.product.amount.balance_format", locale: locale, primaryCurrencyCode)
        case .realEstate:
            return QuickSetupLocalization.format("quick_setup.product.amount.value_format", locale: locale, primaryCurrencyCode)
        case .debt:
            return QuickSetupLocalization.format("quick_setup.product.amount.debt_amount_format", locale: locale, primaryCurrencyCode)
        case .credit:
            return QuickSetupLocalization.format("quick_setup.product.amount.outstanding_debt_format", locale: locale, primaryCurrencyCode)
        case .crypto, .ticker:
            return QuickSetupLocalization.tr("quick_setup.product.amount.quantity", locale: locale)
        }
    }

    var productNamePlaceholder: String {
        let locale = presentationLocale
        switch productTypeForCreation {
        case .card:
            return AppLocalization.string("finances.add_account.placeholder.card", locale: locale)
        case .realEstate:
            return AppLocalization.string("finances.add_account.placeholder.investment.house", locale: locale)
        case .debt:
            return AppLocalization.string("finances.add_account.placeholder.investment.debt", locale: locale)
        case .credit:
            return AppLocalization.string("finances.add_account.placeholder.credit", locale: locale)
        case .crypto, .ticker:
            return AppLocalization.string("finances.add_account.placeholder.market", locale: locale)
        }
    }

    var productPurchasePriceTitle: String {
        let locale = presentationLocale
        return productTypeForCreation == .crypto
            ? QuickSetupLocalization.tr("quick_setup.product.purchase_price.coin", locale: locale)
            : QuickSetupLocalization.tr("quick_setup.product.purchase_price.share", locale: locale)
    }

    var productQuantityFractionDigits: Int {
        productTypeForCreation == .crypto
            ? AmountInputFormatter.marketQuantityFractionDigits
            : AmountInputFormatter.defaultFractionDigits
    }

    var productUnitPriceFractionDigits: Int {
        productTypeForCreation == .crypto
            ? AmountInputFormatter.marketPriceFractionDigits
            : AmountInputFormatter.defaultFractionDigits
    }

    var productMarketSearchTitle: String {
        let locale = presentationLocale
        return productTypeForCreation == .crypto
            ? QuickSetupLocalization.tr("quick_setup.market_search.pair", locale: locale)
            : QuickSetupLocalization.tr("quick_setup.market_search.ticker", locale: locale)
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
        let locale = presentationLocale
        switch currentStep {
        case .summary:
            return QuickSetupLocalization.tr("quick_setup.common.finish", locale: locale)
        default:
            return QuickSetupLocalization.tr("quick_setup.common.continue", locale: locale)
        }
    }

    var shouldPromptForPrimaryProductEntry: Bool {
        products.isEmpty
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
            groups: groups,
            products: products,
            backupPreference: hasCustomizedBackupPreference ? backupPreference : initialBackupPreference
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

    func toggleFavoriteCurrency(_ rawCode: String) -> FavoriteCurrencyToggleResult {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return .ignored }
        guard code != primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else { return .ignored }

        if let index = favoriteCurrencyCodes.firstIndex(of: code) {
            favoriteCurrencyCodes.remove(at: index)
            return .removed
        }

        guard favoriteCurrencyCodes.count < Self.maxFavoriteCurrencies else { return .ignored }
        favoriteCurrencyCodes.insert(code, at: 0)
        return .added
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

    func selectAllExpenseCategories() {
        selectedExpenseCategoryIDs = Set(Self.allExpenseCategoryIDs)
    }

    func clearExpenseCategories() {
        selectedExpenseCategoryIDs.removeAll()
    }

    func selectProductType(_ type: QuickSetupProductType) {
        guard availableProductTypes.contains(type) else { return }
        hasExplicitlySelectedProductType = true
        productTypeForCreation = type
        resetDraftInputs(keepingTypeSpecificData: false)
    }

    func addGroupPreset(_ preset: QuickSetupGroupPreset) {
        let locale = presentationLocale
        let targetName = normalizeGroupName(preset.title(for: locale))
        if let existing = groups.first(where: { normalizeGroupName($0.name) == targetName }) {
            selectedGroupDraftID = existing.id
            return
        }

        let draft = preset.draft(for: locale)
        groups.append(draft)
        selectedGroupDraftID = draft.id
    }

    func chooseGroupPreset(_ preset: QuickSetupGroupPreset) {
        setGroups(from: [preset])
    }

    func selectGroupDraft(id: UUID?) {
        selectedGroupDraftID = id
    }

    func clearProducts() {
        products.removeAll()
    }

    func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        products = products.map { product in
            guard product.groupDraftID == id else { return product }
            return QuickSetupProductDraft(
                id: product.id,
                type: product.type,
                name: product.name,
                amount: product.amount,
                currencyCode: product.currencyCode,
                groupDraftID: nil,
                marketSnapshot: product.marketSnapshot,
                visualIcon: product.visualIcon
            )
        }

        if selectedGroupDraftID == id {
            selectedGroupDraftID = groups.first?.id
        }
    }

    private func setGroups(from presets: [QuickSetupGroupPreset]) {
        let locale = presentationLocale
        groups = presets.map { $0.draft(for: locale) }
        selectedGroupDraftID = groups.first?.id
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
        guard let draft = buildDraftProduct() else {
            return false
        }

        products.append(draft)
        resetDraftInputs(keepingTypeSpecificData: false)
        return true
    }

    @discardableResult
    func savePrimaryDraftProduct() -> Bool {
        guard let draft = buildDraftProduct() else {
            return false
        }

        products = [draft]
        resetDraftInputs(keepingTypeSpecificData: false)
        return true
    }

    private func buildDraftProduct() -> QuickSetupProductDraft? {
        lastAddDraftError = nil
        let trimmedName = productNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = productSymbolInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let resolvedName: String
        let amount: Double
        let marketSnapshot: QuickSetupProductMarketSnapshot?

        if productTypeForCreation.isMarketTracked {
            guard !trimmedSymbol.isEmpty else {
                lastAddDraftError = localizedQuickSetupError("quick_setup.error.enter_ticker")
                return nil
            }
            if productTypeForCreation == .crypto, !EntitlementPolicy.canUseQuickSetupCrypto(isPro: isProUser) {
                lastAddDraftError = localizedQuickSetupError("quick_setup.error.crypto_requires_pro")
                return nil
            }
            guard let quantity = parsedDecimal(productQuantityInput), quantity > 0 else {
                lastAddDraftError = localizedQuickSetupError("quick_setup.error.enter_position_quantity")
                return nil
            }
            let purchaseUnitPrice: Double
            if productTypeForCreation == .crypto {
                purchaseUnitPrice = max(0, parsedDecimal(productPurchasePriceInput) ?? 0)
            } else {
                guard let parsedPurchaseUnitPrice = parsedDecimal(productPurchasePriceInput), parsedPurchaseUnitPrice > 0 else {
                    lastAddDraftError = localizedQuickSetupError("quick_setup.error.enter_buy_price")
                    return nil
                }
                purchaseUnitPrice = parsedPurchaseUnitPrice
            }
            let currentTickerDraftCount = products.reduce(into: 0) { partialResult, item in
                if item.type.isMarketTracked {
                    partialResult += 1
                }
            }
            if !EntitlementPolicy.canAddQuickSetupTrackedProduct(
                type: productTypeForCreation,
                isPro: isProUser,
                currentTrackedTickers: currentTickerDraftCount
            ) {
                lastAddDraftError = productTypeForCreation == .crypto
                    ? localizedQuickSetupError("quick_setup.error.crypto_requires_pro")
                    : QuickSetupLocalization.format(
                        "quick_setup.error.tracked_ticker_limit_format",
                        locale: presentationLocale,
                        EntitlementPolicy.freeQuickSetupTrackedTickerLimit
                    )
                return nil
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
                lastAddDraftError = localizedQuickSetupError("quick_setup.error.enter_name")
                return nil
            }
            resolvedName = trimmedName
            amount = max(0, parsedDecimal(productAmountInput) ?? 0)
            marketSnapshot = nil
        }

        let normalizedCurrency = productTypeForCreation.isMarketTracked
            ? productResolvedCurrencyCode
            : primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        return QuickSetupProductDraft(
            type: productTypeForCreation,
            name: resolvedName,
            amount: amount,
            currencyCode: normalizedCurrency.isEmpty ? SettingsManager.defaultPrimaryCurrencyCode : normalizedCurrency,
            groupDraftID: selectedGroupDraftID,
            marketSnapshot: marketSnapshot,
            visualIcon: productTypeForCreation.icon
        )
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

    private func localizedQuickSetupError(_ key: String) -> String {
        QuickSetupLocalization.tr(key, locale: presentationLocale)
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

    private func normalizeGroupName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
