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
        // Swift Testing параллелит тесты внутри таргета: без явной фиксации языка
        // тест зависит от ambient LanguageManager.shared, который другие l10n-тесты
        // временно переключают (withLanguage). Пиним язык, как это делают остальные
        // l10n-тесты в проекте (см. AppLanguageTestSupport).
        AppLanguageTestSupport.withLanguage(.russian) {
            #expect(
                FinanceOverviewLedgerStyle.countsText(groups: 3, accounts: 4) == "3 групп · 4 счетов"
            )
        }
    }

    @Test("Style helper собирает компактную строку для плотной карточки")
    func compactCountsTextBuildsExpectedCopy() {
        AppLanguageTestSupport.withLanguage(.russian) {
            #expect(
                FinanceOverviewLedgerStyle.compactCountsText(groups: 3, accounts: 4) == "3 гр. · 4 сч."
            )
        }
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


    // MARK: - stackedSegmentWidths (Гейт 5c.7.6.1 — полоса «активы vs обязательства»)

    @Test("Сегменты стековой полосы суммируются в доступную ширину (не как независимые бары)")
    func stackedSegmentWidthsSumToAvailableWidth() {
        let widths = FinanceOverviewLedgerStyle.stackedSegmentWidths(
            debitTotal: 700, creditTotal: 300, availableWidth: 200, minimumSegmentWidth: 6
        )
        #expect(abs((widths.debit + widths.credit) - 200) < 0.001)
        #expect(widths.debit > widths.credit)
    }

    @Test("Только активы (обязательств нет) — вся ширина одному сегменту")
    func stackedSegmentWidthsAllDebit() {
        let widths = FinanceOverviewLedgerStyle.stackedSegmentWidths(
            debitTotal: 500, creditTotal: 0, availableWidth: 200, minimumSegmentWidth: 6
        )
        #expect(widths.debit == 200)
        #expect(widths.credit == 0)
    }

    @Test("Только обязательства (активов нет) — вся ширина другому сегменту")
    func stackedSegmentWidthsAllCredit() {
        let widths = FinanceOverviewLedgerStyle.stackedSegmentWidths(
            debitTotal: 0, creditTotal: 500, availableWidth: 200, minimumSegmentWidth: 6
        )
        #expect(widths.debit == 0)
        #expect(widths.credit == 200)
    }

    @Test("Малая доля (напр. 1%) не схлопывается в 0 — держит минимальную видимость, сумма ширины сохраняется")
    func stackedSegmentWidthsGuaranteesMinimumVisibility() {
        let widths = FinanceOverviewLedgerStyle.stackedSegmentWidths(
            debitTotal: 9_900, creditTotal: 100, availableWidth: 200, minimumSegmentWidth: 12
        )
        #expect(widths.credit >= 12)
        #expect(abs((widths.debit + widths.credit) - 200) < 0.001)
    }

    @Test("Обе стороны пустые (gross == 0) — не крашится, отдаёт всю ширину нейтрально дебету")
    func stackedSegmentWidthsZeroGross() {
        let widths = FinanceOverviewLedgerStyle.stackedSegmentWidths(
            debitTotal: 0, creditTotal: 0, availableWidth: 200, minimumSegmentWidth: 6
        )
        #expect(widths.debit == 200)
        #expect(widths.credit == 0)
    }

    @Test("Нулевая доступная ширина — обе стороны 0, без деления на ноль")
    func stackedSegmentWidthsZeroAvailableWidth() {
        let widths = FinanceOverviewLedgerStyle.stackedSegmentWidths(
            debitTotal: 500, creditTotal: 300, availableWidth: 0, minimumSegmentWidth: 6
        )
        #expect(widths.debit == 0)
        #expect(widths.credit == 0)
    }
}
