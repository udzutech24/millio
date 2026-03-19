//
//  CashflowInsightsChartModelsTests.swift
//  millioTests
//
//  Created by Codex on 08.03.2026.
//

import Foundation
import Testing
@testable import millio

struct CashflowInsightsChartModelsTests {
    @Test("График по диапазону сравнивает карточки с предыдущим диапазоном той же длины")
    func presentationAggregatesSelectedDateRange() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let start = Self.date(2026, 2, 7)
        let end = Self.date(2026, 3, 9)

        let presentation = CashflowInsightsChartBuilder.makePresentation(
            entries: [
                .init(id: "outside", date: Self.date(2026, 1, 20), income: 0, expense: 999),
                .init(id: "prev-income", date: Self.date(2026, 1, 10), income: 200, expense: 0),
                .init(id: "prev-expense", date: Self.date(2026, 2, 1), income: 0, expense: 70),
                .init(id: "cur-expense-a", date: Self.date(2026, 2, 10), income: 0, expense: 100),
                .init(id: "cur-income", date: Self.date(2026, 2, 20), income: 300, expense: 0),
                .init(id: "cur-expense-b", date: Self.date(2026, 3, 2), income: 0, expense: 50)
            ],
            dateRange: start...end,
            granularity: .month,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.bars.map(\.label) == ["Feb'26", "Mar'26"])
        #expect(abs(presentation.expenseCard.amount - 150) < 0.01)
        #expect(abs(presentation.incomeCard.amount - 300) < 0.01)
        #expect(abs(presentation.expenseCard.delta - (150 - 1_069)) < 0.01)
        #expect(presentation.expenseCard.deltaTone == .positive)
        #expect(abs(presentation.incomeCard.delta - (300 - 200)) < 0.01)
        #expect(presentation.incomeCard.deltaTone == .positive)
    }

    @Test("Рост расходов помечается как негативный delta, падение расходов как позитивный")
    func expenseDeltaToneIsReversed() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let start = Self.date(2026, 2, 1)
        let end = Self.date(2026, 2, 28)

        let growthCard = CashflowInsightsChartBuilder.makePresentation(
            entries: [
                .init(id: "prev", date: Self.date(2026, 1, 10), income: 0, expense: 100),
                .init(id: "current", date: Self.date(2026, 2, 10), income: 0, expense: 160)
            ],
            dateRange: start...end,
            granularity: .month,
            calendar: calendar,
            locale: locale
        ).expenseCard

        let declineCard = CashflowInsightsChartBuilder.makePresentation(
            entries: [
                .init(id: "prev", date: Self.date(2026, 1, 10), income: 0, expense: 160),
                .init(id: "current", date: Self.date(2026, 2, 10), income: 0, expense: 100)
            ],
            dateRange: start...end,
            granularity: .month,
            calendar: calendar,
            locale: locale
        ).expenseCard

        #expect(growthCard.deltaTone == .negative)
        #expect(declineCard.deltaTone == .positive)
    }

    @Test("Диапазон периода для месяца возвращает крайние дни месяца")
    func periodRangeReturnsMonthBounds() {
        let calendar = Calendar(identifier: .gregorian)
        let periodStart = Self.date(2026, 2, 1)

        let range = CashflowInsightsChartBuilder.periodRange(
            for: periodStart,
            granularity: .month,
            calendar: calendar
        )

        #expect(range.lowerBound == Self.date(2026, 2, 1))
        #expect(range.upperBound == Self.date(2026, 2, 28))
    }

    @Test("Full-screen presentation ограничивает количество видимых месяцев")
    func fullScreenPresentationRespectsMaxVisiblePeriods() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let referenceDate = Self.date(2026, 3, 15)

        let entries: [CashflowConvertedTransaction] = [
            .init(id: "dec", date: Self.date(2025, 12, 10), income: 100, expense: 0),
            .init(id: "jan", date: Self.date(2026, 1, 10), income: 110, expense: 0),
            .init(id: "feb", date: Self.date(2026, 2, 10), income: 120, expense: 0),
            .init(id: "mar", date: Self.date(2026, 3, 10), income: 130, expense: 0)
        ]

        let presentation = CashflowInsightsChartBuilder.makeFullScreenPresentation(
            entries: entries,
            granularity: .month,
            selectedPeriodStart: nil,
            referenceDate: referenceDate,
            maxVisiblePeriods: 3,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.bars.count == 3)
        #expect(presentation.bars.map(\.label) == ["Jan'26", "Feb'26", "Mar'26"])
        #expect(presentation.selectedPeriodStart == Self.date(2026, 3, 1))
    }

    @Test("Режим 12 месяцев может показывать месяцы цифрами")
    func fullScreenPresentationUsesNumericMonthLabelsWhenRequested() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "ru_RU")
        let referenceDate = Self.date(2026, 12, 15)

        let entries: [CashflowConvertedTransaction] = [
            .init(id: "jan", date: Self.date(2026, 1, 10), income: 100, expense: 0),
            .init(id: "jun", date: Self.date(2026, 6, 10), income: 100, expense: 0),
            .init(id: "dec", date: Self.date(2026, 12, 10), income: 100, expense: 0)
        ]

        let presentation = CashflowInsightsChartBuilder.makeFullScreenPresentation(
            entries: entries,
            granularity: .month,
            selectedPeriodStart: nil,
            referenceDate: referenceDate,
            maxVisiblePeriods: 12,
            monthLabelStyle: .monthNumber,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.bars.count == 12)
        #expect(presentation.bars.map(\.label) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"])
        #expect(presentation.selectedPeriodStart == Self.date(2026, 12, 1))
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}
