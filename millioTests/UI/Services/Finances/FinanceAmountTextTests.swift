//
//  FinanceAmountTextTests.swift
//  millioTests
//

import Testing
@testable import millio

@Suite(.serialized)
struct FinanceAmountTextTests {
    @Test("decimal форматирует с пробелами и без дробной части по умолчанию")
    func testDecimalFormatting() {
        #expect(FinanceAmountText.decimal(value: 0) == "0")
        #expect(FinanceAmountText.decimal(value: 12) == "12")
        #expect(FinanceAmountText.decimal(value: 1234) == "1 234")
        #expect(FinanceAmountText.decimal(value: 1234567) == "1 234 567")
    }

    @Test("maskedDigits возвращает минимум 3 точки и зависит от разрядности")
    func testMaskedDigits() {
        #expect(FinanceAmountText.maskedDigits(for: 0) == "•••")
        #expect(FinanceAmountText.maskedDigits(for: 12) == "•••")
        #expect(FinanceAmountText.maskedDigits(for: 123) == "•••")
        #expect(FinanceAmountText.maskedDigits(for: 1234) == "••••")
        #expect(FinanceAmountText.maskedDigits(for: 1234567) == "•••••••")
        #expect(FinanceAmountText.maskedDigits(for: -1234) == "•••••")
    }

    @Test("withCurrency маскирует сумму, но оставляет символ валюты")
    func testWithCurrencyHidden() {
        let text = FinanceAmountText.withCurrency(value: 1620746, currencySymbol: "₽", isHidden: true)
        #expect(text == "••••••• ₽")
    }

    @Test("withCurrency показывает сумму и символ валюты если не скрыто")
    func testWithCurrencyVisible() {
        let text = FinanceAmountText.withCurrency(value: 1620746, currencySymbol: "₽", isHidden: false)
        #expect(text == "1 620 746 ₽")
    }

    @Test("percent маскирует проценты в privacy-режиме")
    func testPercentHidden() {
        #expect(FinanceAmountText.percent(value: 0.2, isHidden: true) == "•••%")
        #expect(FinanceAmountText.percent(value: -12.5, isHidden: true) == "•••%")
    }

    @Test("percent форматирует знак и дробную часть когда privacy-режим выключен")
    func testPercentVisible() {
        #expect(FinanceAmountText.percent(value: 0.2, isHidden: false) == "+0.2%")
        #expect(FinanceAmountText.percent(value: -12.5, isHidden: false) == "-12.5%")
    }

    @Test("isPercentUndefined: near-zero база (sentinel ±999999) → процент не определён и НЕ рендерится")
    func testPercentUndefinedForSentinel() {
        // Решение владельца 2026-07-13: при near-zero базе процент не показываем совсем.
        #expect(FinanceAmountText.isPercentUndefined(value: 999999, isHidden: false) == true)
        #expect(FinanceAmountText.isPercentUndefined(value: -999999, isHidden: false) == true)
        #expect(FinanceAmountText.isPercentUndefined(value: 1_000_000, isHidden: false) == true)
    }

    @Test("isPercentUndefined: обычный процент → определён (рендерится числом, не скрыт)")
    func testPercentDefinedForNormalValue() {
        #expect(FinanceAmountText.isPercentUndefined(value: 0.2, isHidden: false) == false)
        #expect(FinanceAmountText.isPercentUndefined(value: -12.5, isHidden: false) == false)
        #expect(FinanceAmountText.isPercentUndefined(value: 999998, isHidden: false) == false)
    }

    @Test("isPercentUndefined: privacy-режим (isHidden) имеет приоритет — рендерим маску, не 'undefined'")
    func testPercentUndefinedRespectsPrivacyMasking() {
        // isHidden → показываем маскированные точки (отдельная логика), поэтому НЕ undefined.
        #expect(FinanceAmountText.isPercentUndefined(value: 999999, isHidden: true) == false)
        #expect(FinanceAmountText.isPercentUndefined(value: 0.2, isHidden: true) == false)
    }
}
