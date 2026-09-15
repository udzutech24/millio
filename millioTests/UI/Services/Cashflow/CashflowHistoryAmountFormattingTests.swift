import Foundation
import Testing
@testable import millio

/// Регрессия для п.7 пакета фиксов 2.0(6): cashflowHistoryAmountText раньше игнорировал
/// AppLocalization.currentAppLocale и всегда форматировал число по-русски (пробел-тысячи,
/// запятая-дробь), даже при English UI. Теперь локаль передаётся явно и число должно
/// идти по ней, плюс опциональный символ валюты операции.
@Suite
struct CashflowHistoryAmountFormattingTests {
    @Test("En locale форматирует запятой-тысячи и точкой-дробью")
    func testEnglishLocaleGrouping() {
        let text = cashflowHistoryAmountText(1234.5, locale: Locale(identifier: "en_US"))
        #expect(text == "1,234.5")
    }

    @Test("Ru locale форматирует пробелом-тысячи и запятой-дробью")
    func testRussianLocaleGrouping() {
        let text = cashflowHistoryAmountText(1234.5, locale: Locale(identifier: "ru_RU"))
        #expect(text.contains(","))
        #expect(!text.contains("1,234"))
    }

    @Test("currencyCode добавляет символ валюты рядом с числом")
    func testCurrencySymbolAppended() {
        let text = cashflowHistoryAmountText(100, currencyCode: "USD", locale: Locale(identifier: "en_US"))
        #expect(text == "100 \(MonetaCurrency.USD.symbol)")
    }

    @Test("Без currencyCode символ не добавляется (обратная совместимость)")
    func testNoCurrencyCodeNoSymbol() {
        let text = cashflowHistoryAmountText(100, locale: Locale(identifier: "en_US"))
        #expect(text == "100")
    }

    @Test("cashflowHistoryWholeAmountText уважает переданную локаль")
    func testWholeAmountRespectsLocale() {
        let text = cashflowHistoryWholeAmountText(2500, locale: Locale(identifier: "en_US"))
        #expect(text == "2,500")
    }
}
