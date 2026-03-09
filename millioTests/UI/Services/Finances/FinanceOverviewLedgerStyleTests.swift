//
//  FinanceOverviewLedgerStyleTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import CoreGraphics
import Testing
@testable import millio

struct FinanceOverviewLedgerStyleTests {
    @Test("Style helper собирает строку количества групп и счетов")
    func countsTextBuildsExpectedCopy() {
        #expect(
            FinanceOverviewLedgerStyle.countsText(groups: 3, accounts: 4) == "3 групп · 4 счетов"
        )
    }

    @Test("Style helper меняет подпись раскрытия по состоянию")
    func disclosureTextReflectsExpandedState() {
        #expect(FinanceOverviewLedgerStyle.disclosureText(isExpanded: false) == "Показать детали")
        #expect(FinanceOverviewLedgerStyle.disclosureText(isExpanded: true) == "Свернуть")
    }

    @Test("Style helper ограничивает ширину прогресс-бара минимальным значением")
    func barWidthRespectsMinimumValue() {
        let width = FinanceOverviewLedgerStyle.barWidth(
            total: 1,
            reference: 10_000,
            availableWidth: 120,
            minimumWidth: 28
        )

        #expect(width == 28)
    }

    @Test("Style helper не дает бару выйти за доступную ширину")
    func barWidthDoesNotExceedAvailableWidth() {
        let width = FinanceOverviewLedgerStyle.barWidth(
            total: 15_000,
            reference: 10_000,
            availableWidth: 120,
            minimumWidth: 28
        )

        #expect(width == CGFloat(120))
    }
}
