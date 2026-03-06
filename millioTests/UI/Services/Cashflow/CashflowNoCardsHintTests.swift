//
//  CashflowNoCardsHintTests.swift
//  millioTests
//

import Testing
@testable import millio

struct CashflowNoCardsHintTests {
    @Test("Показываем хинт, когда нет записей и нет карт")
    func showsHintWhenNoEntriesAndNoCards() {
        #expect(cashflowShouldShowNoCardsHint(hasEntries: false, hasAvailableCards: false))
    }

    @Test("Не показываем хинт, когда есть записи")
    func hidesHintWhenEntriesExist() {
        #expect(!cashflowShouldShowNoCardsHint(hasEntries: true, hasAvailableCards: false))
    }

    @Test("Не показываем хинт, когда карты есть")
    func hidesHintWhenCardsExist() {
        #expect(!cashflowShouldShowNoCardsHint(hasEntries: false, hasAvailableCards: true))
    }
}
