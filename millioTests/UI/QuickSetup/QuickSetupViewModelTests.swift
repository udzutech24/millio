import XCTest
@testable import millio

@MainActor
final class QuickSetupViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "favoriteCurrencyCodes")
        UserDefaults.standard.removeObject(forKey: "quickSetupExpenseCategoryIDs")
        UserDefaults.standard.removeObject(forKey: "primaryCurrencyCode")
    }

    func testToggleFavoriteCurrencyEnforcesLimitAndPrimaryExclusion() {
        let appState = AppState()
        appState.primaryCurrencyCode = "USD"
        let viewModel = QuickSetupViewModel(appState: appState)

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

    func testAddDraftProductRequiresNameAndResetsInputs() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(appState: appState)

        viewModel.productTypeForCreation = .ticker
        viewModel.productNameInput = ""
        viewModel.productSymbolInput = "AAPL"
        viewModel.productAmountInput = "1000"

        XCTAssertTrue(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.products.count, 1)
        XCTAssertEqual(viewModel.products.first?.symbol, "AAPL")
        XCTAssertEqual(viewModel.products.first?.name, "AAPL")
        XCTAssertEqual(viewModel.productNameInput, "")
        XCTAssertEqual(viewModel.productSymbolInput, "")
        XCTAssertEqual(viewModel.productAmountInput, "")
    }

    func testMakeSelectionNormalizesFavoriteCurrencies() {
        let appState = AppState()
        appState.primaryCurrencyCode = "RUB"
        let viewModel = QuickSetupViewModel(appState: appState)

        viewModel.favoriteCurrencyCodes = ["usd", "EUR", "RUB", "usd"]
        let selection = viewModel.makeSelection()

        XCTAssertEqual(selection.primaryCurrencyCode, "RUB")
        XCTAssertEqual(selection.favoriteCurrencyCodes, ["USD", "EUR"])
        XCTAssertEqual(selection.backupPreference, .localOnly)
    }

    func testTickerWithoutSymbolFails() {
        let appState = AppState()
        let viewModel = QuickSetupViewModel(appState: appState)

        viewModel.productTypeForCreation = .ticker
        viewModel.productNameInput = "Apple"
        viewModel.productSymbolInput = ""
        viewModel.productAmountInput = "1000"

        XCTAssertFalse(viewModel.addDraftProduct())
        XCTAssertTrue(viewModel.products.isEmpty)
    }

    func testBackupPreferenceFollowsAppState() {
        let appState = AppState()
        appState.isBackupEnabled = true
        let viewModel = QuickSetupViewModel(appState: appState)

        XCTAssertEqual(viewModel.backupPreference, .cloudBackup)

        viewModel.backupPreference = .localOnly
        let selection = viewModel.makeSelection()
        XCTAssertEqual(selection.backupPreference, .localOnly)
    }
}
