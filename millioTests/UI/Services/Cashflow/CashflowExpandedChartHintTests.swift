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
        #expect(text.contains("Окно 4"))
    }

    @Test("Hint для английского языка содержит рекомендуемое окно")
    func englishHintContainsVisibleRange() {
        let text = cashflowExpandedHintText(visiblePeriods: 12, locale: Locale(identifier: "en_US"))
        #expect(text.contains("Range 12"))
    }
}

