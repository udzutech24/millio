//
//  CashflowTransactionsHistoryViewTests.swift
//  millioTests
//
//  Created by Assistant on 13.03.2026.
//

import Testing
@testable import millio

struct CashflowTransactionsHistoryViewTests {
    @Test("Активная группа фильтров показывает выбранный тип и диапазон дат")
    func activeFiltersIncludeSelectedTypeAndDate() {
        let items = CashflowHistoryFilterPresentation.activeItems(
            selectedFilter: .income,
            dateFilterTitle: "10 марта - 13 марта",
            isDateFilterActive: true
        )

        #expect(items == [
            .type(.income),
            .date("10 марта - 13 марта")
        ])
    }

    @Test("Активная группа фильтров скрыта для фильтра Все без дат")
    func activeFiltersStayEmptyForDefaultState() {
        let items = CashflowHistoryFilterPresentation.activeItems(
            selectedFilter: .all,
            dateFilterTitle: "Период",
            isDateFilterActive: false
        )

        #expect(items.isEmpty)
    }
}
