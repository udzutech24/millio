//
//  MainQuickActionIconTests.swift
//  millioTests
//
//  Created by Codex on 03.03.2026.
//

import Testing
@testable import millio

struct MainQuickActionIconTests {
    @Test("Иконки быстрых действий соответствуют SF Symbols, используемым в Cashflow")
    func quickActionIconsMatchCashflowSymbols() {
        #expect(QuickActionIcons.income == "plus")
        #expect(QuickActionIcons.expense == "minus")
        #expect(QuickActionIcons.transfer == "arrow.left.arrow.right")
    }
}
