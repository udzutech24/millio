//
//  CashflowChartVariantALayoutTests.swift
//  millioTests
//
//  Редизайн графика Cashflow — вариант A (§7.6 плана): нормализация шкалы,
//  net-offset, пустые/нулевые месяцы, один месяц.
//

import Foundation
import Testing
@testable import millio

struct CashflowChartVariantALayoutTests {
    private func bar(_ date: Date, income: Double, expense: Double, isPlaceholder: Bool = false) -> CashflowInsightsBar {
        CashflowInsightsBar(
            id: date,
            periodStart: date,
            label: "test",
            income: income,
            expense: expense,
            isPlaceholder: isPlaceholder
        )
    }

    @Test("Единая шкала: максимум берётся из всех видимых месяцев, а не только выбранного")
    func scaleUsesMaxAcrossAllVisibleBars() {
        let d1 = Date(timeIntervalSince1970: 0)
        let d2 = Date(timeIntervalSince1970: 1)
        let bars = [bar(d1, income: 100, expense: 10), bar(d2, income: 20, expense: 500)]
        #expect(CashflowChartVariantALayout.scale(bars: bars) == 500)
    }

    @Test("Высота бара строго пропорциональна доле от общей шкалы")
    func barHeightIsStrictlyProportional() {
        let d1 = Date(timeIntervalSince1970: 0)
        let d2 = Date(timeIntervalSince1970: 1)
        // Доход d2 ровно в 2 раза меньше d1 → высота тоже должна быть ровно в 2 раза меньше.
        let bars = [bar(d1, income: 200, expense: 0), bar(d2, income: 100, expense: 0)]
        let layouts = CashflowChartVariantALayout.barLayouts(bars: bars, halfHeight: 100)

        #expect(layouts[0].incomeHeight == 100)
        #expect(layouts[1].incomeHeight == 50)
    }

    @Test("Пустой месяц (нет транзакций) — высота 0, а не минимальная видимая")
    func emptyMonthGivesZeroHeight() {
        let d1 = Date(timeIntervalSince1970: 0)
        let bars = [bar(d1, income: 0, expense: 0, isPlaceholder: true)]
        let layouts = CashflowChartVariantALayout.barLayouts(bars: bars, halfHeight: 100)

        #expect(layouts[0].incomeHeight == 0)
        #expect(layouts[0].expenseHeight == 0)
        #expect(layouts[0].netOffset == 0)
    }

    @Test("Крошечная ненулевая сумма всё ещё видна (минимальная высота), но не завышена")
    func tinyNonZeroValueStaysVisible() {
        let d1 = Date(timeIntervalSince1970: 0)
        let d2 = Date(timeIntervalSince1970: 1)
        let bars = [bar(d1, income: 1_000_000, expense: 0), bar(d2, income: 1, expense: 0)]
        let layouts = CashflowChartVariantALayout.barLayouts(bars: bars, halfHeight: 200)

        #expect(layouts[1].incomeHeight == CashflowChartVariantALayout.minimumVisibleHeight)
        #expect(layouts[0].incomeHeight == 200)
    }

    @Test("Один месяц в списке — не падает, бар занимает всю шкалу")
    func singleBarFillsScale() {
        let d1 = Date(timeIntervalSince1970: 0)
        let bars = [bar(d1, income: 50, expense: 30)]
        let layouts = CashflowChartVariantALayout.barLayouts(bars: bars, halfHeight: 100)

        #expect(layouts.count == 1)
        #expect(layouts[0].incomeHeight == 100)
        #expect(layouts[0].expenseHeight == 60)
    }

    @Test("Все месяцы нулевые — деление на ноль не происходит, всё 0")
    func allZeroBarsStayZero() {
        let d1 = Date(timeIntervalSince1970: 0)
        let d2 = Date(timeIntervalSince1970: 1)
        let bars = [bar(d1, income: 0, expense: 0), bar(d2, income: 0, expense: 0)]
        let layouts = CashflowChartVariantALayout.barLayouts(bars: bars, halfHeight: 100)

        #expect(layouts.allSatisfy { $0.incomeHeight == 0 && $0.expenseHeight == 0 && $0.netOffset == 0 })
    }

    @Test("Net-offset положительный при income > expense и отрицательный при обратном")
    func netOffsetSignMatchesNetDirection() {
        let d1 = Date(timeIntervalSince1970: 0)
        let d2 = Date(timeIntervalSince1970: 1)
        let bars = [bar(d1, income: 100, expense: 40), bar(d2, income: 40, expense: 100)]
        let layouts = CashflowChartVariantALayout.barLayouts(bars: bars, halfHeight: 100)

        #expect(layouts[0].netOffset > 0)
        #expect(layouts[0].isPositiveNet)
        #expect(layouts[1].netOffset < 0)
        #expect(!layouts[1].isPositiveNet)
    }

    @Test("Net-offset никогда не выходит за пределы halfHeight (clamp)")
    func netOffsetIsClampedToHalfHeight() {
        let d1 = Date(timeIntervalSince1970: 0)
        // expense = 0 делает net равным income, что при равенстве maxValue даёт net/maxValue == 1 → offset == halfHeight ровно.
        let bars = [bar(d1, income: 100, expense: 0)]
        let layouts = CashflowChartVariantALayout.barLayouts(bars: bars, halfHeight: 100)

        #expect(layouts[0].netOffset <= 100)
        #expect(layouts[0].netOffset >= -100)
    }

    @Test("Пустой список баров — не падает, возвращает пустой массив")
    func emptyBarsListReturnsEmptyLayouts() {
        let layouts = CashflowChartVariantALayout.barLayouts(bars: [], halfHeight: 100)
        #expect(layouts.isEmpty)
    }

    @Test("halfHeight == 0 — не падает и не делит на ноль, все высоты 0")
    func zeroHalfHeightIsSafe() {
        let d1 = Date(timeIntervalSince1970: 0)
        let bars = [bar(d1, income: 100, expense: 50)]
        let layouts = CashflowChartVariantALayout.barLayouts(bars: bars, halfHeight: 0)

        #expect(layouts[0].incomeHeight == 0)
        #expect(layouts[0].expenseHeight == 0)
        #expect(layouts[0].netOffset == 0)
    }
}
