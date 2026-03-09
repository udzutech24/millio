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
}
