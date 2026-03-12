import XCTest
@testable import millio

private struct QuickSetupMarketDataClientMock: MarketDataClientProtocol {
    var latestPriceValue: Double?

    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol] {
        []
    }

    func latestPrice(symbol: String, forceRefresh: Bool) async throws -> Double? {
        latestPriceValue
    }
}

@MainActor
final class QuickSetupViewModelTests: XCTestCase {
    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "QuickSetupViewModelTests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removeObject(forKey: "favoriteCurrencyCodes")
        UserDefaults.standard.removeObject(forKey: "quickSetupExpenseCategoryIDs")
        UserDefaults.standard.removeObject(forKey: "primaryCurrencyCode")
    }

    override func tearDown() {
        isolatedDefaults?.removePersistentDomain(forName: suiteName)
        isolatedDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testToggleFavoriteCurrencyEnforcesLimitAndPrimaryExclusion() {
        let appState = AppState()
        appState.primaryCurrencyCode = "USD"
        isolatedDefaults.set("USD", forKey: "primaryCurrencyCode")
        let viewModel = QuickSetupViewModel(appState: appState, defaults: isolatedDefaults)

        viewModel.favoriteCurrencyCodes = []
        viewModel.toggleFavoriteCurrency("USD")
        XCTAssertTrue(viewModel.favoriteCurrencyCodes.isEmpty)

        viewModel.toggleFavoriteCurrency("EUR")
        viewModel.toggleFavoriteCurrency("JPY")
        viewModel.toggleFavoriteCurrency("GBP")
        viewModel.toggleFavoriteCurrency("CHF")
        viewModel.toggleFavoriteCurrency("AUD")

        XCTAssertEqual(viewModel.favoriteCurrencyCodes.count, 4)
        XCTAssertFalse(viewModel.favoriteCurrencyCodes.contains("USD"))
    }

    func testChangingPrimaryCurrencyRemovesItFromFavoritesImmediately() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(appState: appState, defaults: isolatedDefaults)

        viewModel.favoriteCurrencyCodes = ["USD", "EUR", "CNY"]
        viewModel.primaryCurrencyCode = "USD"

        XCTAssertEqual(viewModel.favoriteCurrencyCodes, ["EUR", "CNY"])
        XCTAssertFalse(viewModel.favoriteCurrencyCodes.contains("USD"))
    }

    func testLocaleStepRequiresFavoriteCurrenciesToContinue() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(appState: appState, defaults: isolatedDefaults)

        viewModel.currentStep = .localeAndCurrencies
        viewModel.primaryCurrencyCode = "USD"
        viewModel.favoriteCurrencyCodes = []
        XCTAssertFalse(viewModel.canContinue)

        viewModel.favoriteCurrencyCodes = ["EUR"]
        XCTAssertTrue(viewModel.canContinue)
    }

    func testAddDraftProductRequiresNameAndResetsInputs() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(appState: appState, defaults: isolatedDefaults)

        viewModel.productTypeForCreation = .ticker
        viewModel.productSymbolInput = "AAPL"
        viewModel.productQuantityInput = "2"
        viewModel.productPurchasePriceInput = "100"

        XCTAssertTrue(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.products.count, 1)
        XCTAssertEqual(viewModel.products.first?.symbol, "AAPL")
        XCTAssertEqual(viewModel.products.first?.name, "AAPL")
        XCTAssertEqual(viewModel.productSymbolInput, "")
        XCTAssertEqual(viewModel.productQuantityInput, "")
        XCTAssertEqual(viewModel.productPurchasePriceInput, "")
    }

    func testMakeSelectionNormalizesFavoriteCurrencies() {
        let appState = AppState()
        appState.isBackupEnabled = false
        let systemContext = QuickSetupSystemContext(
            preferredLanguageIdentifiers: ["ru-RU"],
            locale: Locale(identifier: "ru_RU")
        )
        let viewModel = QuickSetupViewModel(
            appState: appState,
            systemContext: systemContext,
            defaults: isolatedDefaults
        )

        viewModel.favoriteCurrencyCodes = ["usd", "EUR", "RUB", "usd"]
        let selection = viewModel.makeSelection()

        XCTAssertEqual(selection.primaryCurrencyCode, "RUB")
        XCTAssertEqual(selection.favoriteCurrencyCodes, ["USD", "EUR"])
        XCTAssertEqual(selection.backupPreference, .localOnly)
    }

    func testTickerWithoutSymbolFails() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(appState: appState, defaults: isolatedDefaults)

        viewModel.productTypeForCreation = .ticker
        viewModel.productNameInput = "Apple"
        viewModel.productSymbolInput = ""
        viewModel.productQuantityInput = "2"
        viewModel.productPurchasePriceInput = "100"

        XCTAssertFalse(viewModel.addDraftProduct())
        XCTAssertTrue(viewModel.products.isEmpty)
    }

    func testBackupPreferenceFollowsAppState() {
        let appState = AppState()
        appState.isBackupEnabled = true
        let viewModel = QuickSetupViewModel(appState: appState, defaults: isolatedDefaults)

        XCTAssertEqual(viewModel.backupPreference, .cloudBackup)

        viewModel.backupPreference = .localOnly
        let selection = viewModel.makeSelection()
        XCTAssertEqual(selection.backupPreference, .localOnly)
    }

    func testExpenseCategoryQuickActions() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(appState: appState, defaults: isolatedDefaults)

        viewModel.clearExpenseCategories()
        XCTAssertTrue(viewModel.selectedExpenseCategoryIDs.isEmpty)

        viewModel.applyRecommendedExpenseCategories()
        XCTAssertEqual(
            viewModel.selectedExpenseCategoryIDs,
            Set(QuickSetupViewModel.recommendedExpenseCategoryIDs)
        )
    }

    func testMarketSearchAutoOpenPolicyTriggersOnlyOnTransitionToMarketProduct() {
        XCTAssertTrue(
            QuickSetupProductFlowPolicy.shouldAutoOpenMarketSearch(
                previousType: .card,
                newType: .ticker
            )
        )
        XCTAssertTrue(
            QuickSetupProductFlowPolicy.shouldAutoOpenMarketSearch(
                previousType: .debt,
                newType: .crypto
            )
        )
        XCTAssertFalse(
            QuickSetupProductFlowPolicy.shouldAutoOpenMarketSearch(
                previousType: .ticker,
                newType: .ticker
            )
        )
        XCTAssertFalse(
            QuickSetupProductFlowPolicy.shouldAutoOpenMarketSearch(
                previousType: .crypto,
                newType: .card
            )
        )
    }

    func testQuickSetupHidesRussianWhenSystemLanguageIsNotRussian() {
        let appState = AppState()
        let systemContext = QuickSetupSystemContext(
            preferredLanguageIdentifiers: ["en-US"],
            locale: Locale(identifier: "en_US")
        )

        let viewModel = QuickSetupViewModel(appState: appState, systemContext: systemContext, defaults: isolatedDefaults)

        XCTAssertEqual(viewModel.availableLanguages, [.system, .english])
        XCTAssertEqual(viewModel.primaryCurrencyCode, "USD")
        XCTAssertEqual(viewModel.favoriteCurrencyCodes, ["EUR", "CNY"])
        XCTAssertEqual(Array(viewModel.recommendedCurrencyCodes.prefix(5)), ["USD", "EUR", "CNY", "GBP", "JPY"])
        XCTAssertFalse(viewModel.recommendedCurrencyCodes.contains("RUB"))
        XCTAssertTrue(viewModel.recommendedCurrencyCodes.contains("EUR"))
        XCTAssertTrue(viewModel.recommendedCurrencyCodes.contains("CNY"))
    }

    func testQuickSetupShowsRussianAndRussianCentricCurrenciesForRussianSystem() {
        let appState = AppState()
        let systemContext = QuickSetupSystemContext(
            preferredLanguageIdentifiers: ["ru-RU"],
            locale: Locale(identifier: "ru_RU")
        )

        let viewModel = QuickSetupViewModel(appState: appState, systemContext: systemContext, defaults: isolatedDefaults)

        XCTAssertEqual(viewModel.availableLanguages, [.system, .english, .russian])
        XCTAssertEqual(viewModel.primaryCurrencyCode, "RUB")
        XCTAssertEqual(viewModel.favoriteCurrencyCodes, ["USD", "CNY", "EUR", "TRY"])
        XCTAssertEqual(viewModel.recommendedCurrencyCodes, ["RUB", "USD", "CNY", "EUR", "TRY"])
    }

    func testAddDraftTickerUsesQuantityAndPurchasePriceForMarketSnapshot() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(
            appState: appState,
            marketDataClient: QuickSetupMarketDataClientMock(latestPriceValue: 12.5),
            defaults: isolatedDefaults
        )

        viewModel.selectProductType(.ticker)
        viewModel.applySelectedMarketSymbol(
            TwelveDataSymbol(
                symbol: "AAPL",
                instrumentName: "Apple Inc",
                exchange: "NASDAQ",
                micCode: nil,
                instrumentType: "Common Stock",
                country: "United States",
                currency: "USD"
            )
        )
        viewModel.productQuantityInput = "3"
        viewModel.productPurchasePriceInput = "10"
        viewModel.productNameInput = "Should be ignored"

        XCTAssertTrue(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.products.count, 1)
        XCTAssertEqual(viewModel.products.first?.name, "AAPL")
        XCTAssertEqual(viewModel.products.first?.currencyCode, "USD")
        XCTAssertEqual(viewModel.products.first?.amount, 30)
        XCTAssertEqual(viewModel.products.first?.marketSnapshot?.quantity, 3)
        XCTAssertEqual(viewModel.products.first?.marketSnapshot?.purchaseUnitPrice, 10)
    }

    func testAddDraftCryptoAllowsMissingBuyPriceWhenMarketPriceExists() async {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(
            appState: appState,
            marketDataClient: QuickSetupMarketDataClientMock(latestPriceValue: 12.5),
            defaults: isolatedDefaults
        )

        viewModel.selectProductType(.crypto)
        viewModel.applySelectedMarketSymbol(
            TwelveDataSymbol(
                symbol: "BTC/USD",
                instrumentName: "Bitcoin",
                exchange: "BINANCE",
                micCode: nil,
                instrumentType: "Cryptocurrency",
                country: nil,
                currency: "USD"
            )
        )
        viewModel.productQuantityInput = "2"
        viewModel.productPurchasePriceInput = ""
        await viewModel.refreshSelectedMarketQuote(forceRefresh: true)

        XCTAssertTrue(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.products.count, 1)
        XCTAssertEqual(viewModel.products.first?.amount, 25)
        XCTAssertEqual(viewModel.products.first?.marketSnapshot?.purchaseUnitPrice, 12.5)
    }

    func testAddDraftCryptoAllowsMissingBuyPriceWithoutMarketPrice() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(
            appState: appState,
            marketDataClient: QuickSetupMarketDataClientMock(latestPriceValue: nil),
            defaults: isolatedDefaults
        )

        viewModel.selectProductType(.crypto)
        viewModel.applySelectedMarketSymbol(
            TwelveDataSymbol(
                symbol: "ETH/USD",
                instrumentName: "Ethereum",
                exchange: "BINANCE",
                micCode: nil,
                instrumentType: "Cryptocurrency",
                country: nil,
                currency: "USD"
            )
        )
        viewModel.productQuantityInput = "1.5"
        viewModel.productPurchasePriceInput = ""

        XCTAssertTrue(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.products.count, 1)
        XCTAssertEqual(viewModel.products.first?.amount, 0)
        XCTAssertEqual(viewModel.products.first?.marketSnapshot?.purchaseUnitPrice, 0)
    }

    func testAddDraftCryptoUsesManualCurrentPriceWhenFeedUnavailable() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(
            appState: appState,
            marketDataClient: QuickSetupMarketDataClientMock(latestPriceValue: nil),
            defaults: isolatedDefaults
        )

        viewModel.selectProductType(.crypto)
        viewModel.applySelectedMarketSymbol(
            TwelveDataSymbol(
                symbol: "BTC/USD",
                instrumentName: "Bitcoin",
                exchange: "BINANCE",
                micCode: nil,
                instrumentType: "Cryptocurrency",
                country: nil,
                currency: "USD"
            )
        )
        viewModel.productQuantityInput = "2"
        viewModel.productPurchasePriceInput = ""
        viewModel.productCurrentPriceInput = "69380.78"

        XCTAssertEqual(viewModel.productPositionTotal ?? -1, 138761.56, accuracy: 0.0001)
        XCTAssertTrue(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.products.count, 1)
        XCTAssertEqual(viewModel.products.first?.amount ?? -1, 138761.56, accuracy: 0.0001)
        XCTAssertEqual(viewModel.products.first?.marketSnapshot?.currentUnitPrice ?? -1, 69380.78, accuracy: 0.0001)
    }

    func testNonRussianSystemSanitizesStoredRublePrimaryAndFavorites() {
        let appState = AppState()
        appState.primaryCurrencyCode = "RUB"
        let systemContext = QuickSetupSystemContext(
            preferredLanguageIdentifiers: ["en-US"],
            locale: Locale(identifier: "en_US")
        )

        isolatedDefaults.set("RUB", forKey: "primaryCurrencyCode")
        isolatedDefaults.set(["RUB", "USD", "EUR", "CNY"], forKey: "favoriteCurrencyCodes")
        let previousFavorites = SettingsManager.shared.favoriteCurrencyCodes
        defer { SettingsManager.shared.favoriteCurrencyCodes = previousFavorites }
        SettingsManager.shared.favoriteCurrencyCodes = ["RUB", "USD", "EUR", "CNY"]

        let viewModel = QuickSetupViewModel(appState: appState, systemContext: systemContext, defaults: isolatedDefaults)

        XCTAssertEqual(viewModel.primaryCurrencyCode, "USD")
        XCTAssertEqual(viewModel.favoriteCurrencyCodes, ["EUR", "CNY"])
        XCTAssertFalse(viewModel.favoriteCurrencyCodes.contains("RUB"))
    }

    func testPrimaryRecommendationPrefersLanguageCurrencyWhenLocaleCurrencyDiffers() {
        let appState = AppState()
        let systemContext = QuickSetupSystemContext(
            preferredLanguageIdentifiers: ["en-GB"],
            locale: Locale(identifier: "en_CH")
        )

        let viewModel = QuickSetupViewModel(appState: appState, systemContext: systemContext, defaults: isolatedDefaults)

        XCTAssertEqual(viewModel.primaryCurrencyCode, "USD")
        XCTAssertEqual(viewModel.recommendedCurrencyCodes.first, "USD")
        XCTAssertTrue(viewModel.recommendedCurrencyCodes.contains("CHF"))
    }
}

final class SupportContactResolverTests: XCTestCase {
    func testEmailContactBuildsMailtoURL() {
        let config = SupportContactConfig(
            emailAddress: "hello@millio.app",
            telegramHandle: "millio_help",
            whatsappNumber: "1234567890",
            telegramIconAssetName: "telegram",
            whatsappIconAssetName: "whatsapp"
        )
        let resolver = SupportContactResolver(config: config)

        XCTAssertEqual(resolver.url(for: .email)?.absoluteString, "mailto:hello@millio.app")
    }

    func testTelegramContactBuildsPublicURL() {
        let config = SupportContactConfig(
            emailAddress: "hello@millio.app",
            telegramHandle: "millio_help",
            whatsappNumber: "1234567890",
            telegramIconAssetName: "telegram",
            whatsappIconAssetName: "whatsapp"
        )
        let resolver = SupportContactResolver(config: config)

        XCTAssertEqual(resolver.url(for: .telegram)?.absoluteString, "https://t.me/millio_help")
    }

    func testWhatsAppContactBuildsPublicURL() {
        let config = SupportContactConfig(
            emailAddress: "hello@millio.app",
            telegramHandle: "millio_help",
            whatsappNumber: "1234567890",
            telegramIconAssetName: "telegram",
            whatsappIconAssetName: "whatsapp"
        )
        let resolver = SupportContactResolver(config: config)

        XCTAssertEqual(resolver.url(for: .whatsapp)?.absoluteString, "https://wa.me/1234567890")
    }
}
