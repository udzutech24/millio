//
//  CashflowFormattingTests.swift
//  millioTests
//
//  Created by Codex on 02.03.2026.
//

import Testing
@testable import millio

struct CashflowFormattingTests {
    @Test("Формат суммы в Cashflow не содержит символ валюты")
    func amountTextHasNoCurrencySuffix() {
        #expect(cashflowAmountText(20_791_808) == "20 791 808")
    }

    @Test("Знаковый формат добавляет префиксы плюс и минус")
    func signedAmountText() {
        #expect(cashflowSignedAmountText(2_692_613) == "+2 692 613")
        #expect(cashflowSignedAmountText(-122_148) == "-122 148")
        #expect(cashflowSignedAmountText(0) == "0")
    }

    @Test("Лейбл валюты в тулбаре показывает нормализованный код")
    func toolbarCurrencyCodeUsesUppercasedCode() {
        #expect(cashflowCurrencyCodeLabel(" rub ") == "RUB")
    }
}
