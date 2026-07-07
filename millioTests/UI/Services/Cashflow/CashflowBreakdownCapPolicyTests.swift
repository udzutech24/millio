//
//  CashflowBreakdownCapPolicyTests.swift
//  millioTests
//
//  Фаза 4 редизайна add-flow (§2.4) — cap top-3 в breakdown главного экрана.
//

import Testing
@testable import millio

struct CashflowBreakdownCapPolicyTests {
    @Test("Больше 3 записей — видимы только первые 3 (порядок сохраняется)")
    func capsToTopThreePreservingOrder() {
        let entries = [10, 9, 8, 7, 6]
        let visible = CashflowBreakdownCapPolicy.visibleEntries(from: entries)
        #expect(visible == [10, 9, 8])
    }

    @Test("Ровно 3 записи — cap не отрезает ничего")
    func exactlyThreeStaysIntact() {
        let entries = [10, 9, 8]
        let visible = CashflowBreakdownCapPolicy.visibleEntries(from: entries)
        #expect(visible == entries)
    }

    @Test("R6: пустой список — визуально пуст, без краша")
    func emptyEntriesStaysEmpty() {
        let visible = CashflowBreakdownCapPolicy.visibleEntries(from: [Int]())
        #expect(visible.isEmpty)
    }

    @Test("Больше 3 записей — ссылка 'Показать всё' нужна")
    func showsExpandLinkWhenMoreThanCap() {
        #expect(CashflowBreakdownCapPolicy.showsExpandLink(totalCount: 5))
    }

    @Test("Ровно 3 записи — ссылка не нужна (и так всё видно)")
    func hidesExpandLinkAtExactCap() {
        #expect(!CashflowBreakdownCapPolicy.showsExpandLink(totalCount: 3))
    }

    @Test("R6: 0 записей — ссылка не нужна (нечего показывать)")
    func hidesExpandLinkWhenEmpty() {
        #expect(!CashflowBreakdownCapPolicy.showsExpandLink(totalCount: 0))
    }
}
