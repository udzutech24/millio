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

    @Test("Style helper собирает компактную строку для плотной карточки")
    func compactCountsTextBuildsExpectedCopy() {
        #expect(
            FinanceOverviewLedgerStyle.compactCountsText(groups: 3, accounts: 4) == "3 гр. · 4 сч."
        )
    }

    @Test("Style helper нормализует отрицательные суммы в кредит")
    func normalizeAmountMovesNegativeToCredit() {
        let normalized = FinanceOverviewLedgerStyle.normalizeAmount(-1200, defaultSide: .debit)
        #expect(normalized?.side == .credit)
        #expect(normalized?.amount == 1200)
    }

    @Test("Style helper нормализует положительные суммы без смены стороны")
    func normalizeAmountKeepsPositiveDefaultSide() {
        let normalized = FinanceOverviewLedgerStyle.normalizeAmount(1200, defaultSide: .debit)
        #expect(normalized?.side == .debit)
        #expect(normalized?.amount == 1200)
    }

    @Test("Style helper отбрасывает почти нулевые значения")
    func normalizeAmountDropsNearZero() {
        #expect(FinanceOverviewLedgerStyle.normalizeAmount(0.001, defaultSide: .debit) == nil)
        #expect(FinanceOverviewLedgerStyle.normalizeAmount(-0.001, defaultSide: .debit) == nil)
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

    @Test("Компактная карточка использует сдержанные метрики для overview")
    func compactCardMetricsMatchCompactDesign() {
        let metrics = FinanceOverviewLedgerStyle.compactCardMetrics

        #expect(metrics.titleFontSize == 16)
        #expect(metrics.amountFontSize == 15)
        #expect(metrics.iconSize == 28)
        #expect(metrics.iconFontSize == 11)
        #expect(metrics.progressHeight == 10)
        #expect(metrics.minProgressWidth == 24)
        #expect(metrics.horizontalPadding == 14)
        #expect(metrics.verticalPadding == 12)
        #expect(metrics.cornerRadius == 22)
        #expect(metrics.contentSpacing == 10)
    }
}
