//
//  MainQuickActionsLayoutTests.swift
//  millioTests
//
//  Created by Codex on 19.03.2026.
//

import Testing
@testable import millio

struct MainQuickActionsLayoutTests {
    @Test("На главной доход расположен левее расхода")
    func incomeComesBeforeExpense() {
        #expect(MainQuickActionsLayout.buttonOrder == [.income, .expense])
    }
}
