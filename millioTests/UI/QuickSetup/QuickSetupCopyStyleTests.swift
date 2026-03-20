import XCTest
@testable import millio

@MainActor
final class QuickSetupCopyStyleTests: XCTestCase {
    func testStepSubtitlesDoNotEndWithPeriod() {
        for step in QuickSetupStep.allCases {
            XCTAssertFalse(
                step.subtitle.hasSuffix("."),
                "Quick setup step subtitle should not end with a period: \(step.subtitle)"
            )
        }
    }

    func testBackupPreferenceCopyDoesNotEndWithPeriod() {
        for option in QuickSetupBackupPreference.allCases {
            XCTAssertFalse(
                option.subtitle.hasSuffix("."),
                "Backup preference subtitle should not end with a period: \(option.subtitle)"
            )
            XCTAssertFalse(
                option.details.hasSuffix("."),
                "Backup preference details should not end with a period: \(option.details)"
            )
        }
    }

    func testAddDraftProductValidationErrorsDoNotEndWithPeriod() {
        let appState = AppState()
        appState.selectedLanguage = .russian
        let viewModel = QuickSetupViewModel(appState: appState)

        viewModel.productTypeForCreation = .ticker
        viewModel.productSymbolInput = "AAPL"
        viewModel.productQuantityInput = ""
        viewModel.productPurchasePriceInput = "100"
        XCTAssertFalse(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.lastAddDraftError, "Укажи количество позиции")
        XCTAssertFalse((viewModel.lastAddDraftError ?? "").hasSuffix("."))

        viewModel.productSymbolInput = "AAPL"
        viewModel.productQuantityInput = "2"
        viewModel.productPurchasePriceInput = ""
        XCTAssertFalse(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.lastAddDraftError, "Укажи цену покупки")
        XCTAssertFalse((viewModel.lastAddDraftError ?? "").hasSuffix("."))
    }

    func testAddDraftProductValidationErrorsAreEnglishForEnglishLanguage() {
        let appState = AppState()
        appState.selectedLanguage = .english
        let viewModel = QuickSetupViewModel(appState: appState)

        viewModel.productTypeForCreation = .ticker
        viewModel.productSymbolInput = "AAPL"
        viewModel.productQuantityInput = ""
        viewModel.productPurchasePriceInput = "100"
        XCTAssertFalse(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.lastAddDraftError, "Enter position quantity")

        viewModel.productSymbolInput = "AAPL"
        viewModel.productQuantityInput = "2"
        viewModel.productPurchasePriceInput = ""
        XCTAssertFalse(viewModel.addDraftProduct())
        XCTAssertEqual(viewModel.lastAddDraftError, "Enter buy price")
    }

    func testStepCopyUsesConciseFormulationsInRussian() {
        let locale = Locale(identifier: "ru_RU")
        XCTAssertEqual(QuickSetupStep.localeAndCurrencies.title(for: locale), "Язык и валюты")
        XCTAssertEqual(QuickSetupStep.localeAndCurrencies.subtitle(for: locale), "Выберите язык и валюты")
        XCTAssertEqual(QuickSetupStep.expenseCategories.subtitle(for: locale), "Выберите категории трат")
        XCTAssertEqual(QuickSetupStep.products.title(for: locale), "Продукты")
        XCTAssertEqual(QuickSetupStep.summary.title(for: locale), "Хранение данных")
    }

    func testTickerProductTypeUsesStocksTitleAndTickerSubtitle() {
        let locale = Locale(identifier: "ru_RU")

        XCTAssertEqual(QuickSetupProductType.ticker.title(for: locale), "Акции")
        XCTAssertEqual(QuickSetupProductType.ticker.subtitle(for: locale), "Тикер")
    }

    func testBackupPreferenceCopyUsesOperationalTone() {
        let ruLocale = Locale(identifier: "ru_RU")
        let enLocale = Locale(identifier: "en_US")

        XCTAssertEqual(QuickSetupBackupPreference.localOnly.title(for: ruLocale), "Локальный контур")
        XCTAssertEqual(QuickSetupBackupPreference.localOnly.details(for: ruLocale), "Выгрузку можно включить позже: Профиль -> Backup")
        XCTAssertEqual(QuickSetupBackupPreference.cloudBackup.details(for: ruLocale), "Шифрование: AES-GCM с ключом устройства или парольной фразой")

        XCTAssertEqual(QuickSetupBackupPreference.localOnly.title(for: enLocale), "Local mode")
        XCTAssertEqual(QuickSetupBackupPreference.cloudBackup.title(for: enLocale), "Local + iCloud")
    }
}
