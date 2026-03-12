//
//  CashflowExpandedChartHintTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import Foundation
import Testing
@testable import millio

struct CashflowExpandedChartHintTests {
    @Test("Hint для русского языка содержит рекомендуемое окно")
    func russianHintContainsVisibleRange() {
        let text = cashflowExpandedHintText(visiblePeriods: 4, locale: Locale(identifier: "ru_RU"))
        #expect(text.contains("Диапазон"))
        #expect(text.contains("4"))
        #expect(text != "cashflow.chart.hint_format")
    }

    @Test("Hint для английского языка содержит рекомендуемое окно")
    func englishHintContainsVisibleRange() {
        let text = cashflowExpandedHintText(visiblePeriods: 12, locale: Locale(identifier: "en_US"))
        #expect(text.contains("Range"))
        #expect(text.contains("12"))
        #expect(text != "cashflow.chart.hint_format")
    }
}
