import Foundation
import XCTest
@testable import millio

final class SmartDataResetLocalizationTests: XCTestCase {
    private let ruLocale = Locale(identifier: "ru_RU")
    private let enLocale = Locale(identifier: "en_US")

    func testRussianCoreLabels() {
        XCTAssertEqual(SmartDataResetL10n.navigationTitle(locale: ruLocale), "Умный сброс")
        XCTAssertEqual(SmartDataResetL10n.periodSectionTitle(locale: ruLocale), "Период")
        XCTAssertEqual(SmartDataResetL10n.targetsSectionTitle(locale: ruLocale), "Что удалить")
        XCTAssertEqual(SmartDataResetL10n.previewSectionTitle(locale: ruLocale), "Предпросмотр")
        XCTAssertEqual(SmartDataResetL10n.applyResetButton(isApplying: false, locale: ruLocale), "Применить сброс")
    }

    func testEnglishCoreLabels() {
        XCTAssertEqual(SmartDataResetL10n.navigationTitle(locale: enLocale), "Smart reset")
        XCTAssertEqual(SmartDataResetL10n.periodSectionTitle(locale: enLocale), "Period")
        XCTAssertEqual(SmartDataResetL10n.targetsSectionTitle(locale: enLocale), "What to delete")
        XCTAssertEqual(SmartDataResetL10n.previewSectionTitle(locale: enLocale), "Preview")
        XCTAssertEqual(SmartDataResetL10n.applyResetButton(isApplying: false, locale: enLocale), "Apply reset")
    }

    func testRussianPeriodAndTargetTitles() {
        XCTAssertEqual(SmartDataResetL10n.periodTitle(.allTime, locale: ruLocale), "За всё время")
        XCTAssertEqual(SmartDataResetL10n.periodTitle(.custom, locale: ruLocale), "Произвольный диапазон")

        XCTAssertEqual(SmartDataResetL10n.targetTitle(.operations, locale: ruLocale), "Операции")
        XCTAssertEqual(SmartDataResetL10n.targetTitle(.accountOperations, locale: ruLocale), "Операции по счетам")
        XCTAssertEqual(SmartDataResetL10n.targetTitle(.zeroAccountsInPeriod, locale: ruLocale), "Обнуление баланса в периоде")
    }

    func testRussianCopyHasNoTrailingPeriod() {
        XCTAssertFalse(SmartDataResetL10n.backupRecommendation(locale: ruLocale).hasSuffix("."))
        XCTAssertFalse(SmartDataResetL10n.confirmResetMessage(locale: ruLocale).hasSuffix("."))
    }
}
