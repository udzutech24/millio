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
    @Test("График по месяцам агрегирует доходы и расходы по выбранному месяцу")
    func monthlyPresentationAggregatesSelectedMonth() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let selection = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? Date()

        let presentation = CashflowInsightsChartBuilder.makePresentation(
            entries: [
                CashflowConvertedTransaction(
                    id: "jan-expense",
                    date: calendar.date(from: DateComponents(year: 2026, month: 1, day: 10)) ?? selection,
                    income: 0,
                    expense: 150
                ),
                CashflowConvertedTransaction(
                    id: "feb-income-a",
                    date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 2)) ?? selection,
                    income: 300,
                    expense: 0
                ),
                CashflowConvertedTransaction(
                    id: "feb-income-b",
                    date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 20)) ?? selection,
                    income: 200,
                    expense: 0
                ),
                CashflowConvertedTransaction(
                    id: "feb-expense",
                    date: calendar.date(from: DateComponents(year: 2026, month: 2, day: 14)) ?? selection,
                    income: 0,
                    expense: 90
                )
            ],
            granularity: .month,
            selectedPeriodStart: selection,
            referenceDate: selection,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.bars.count == 4)
        #expect(presentation.selectedPeriodStart == selection)
        #expect(abs(presentation.expenseCard.amount - 90) < 0.01)
        #expect(abs(presentation.incomeCard.amount - 500) < 0.01)
        #expect(presentation.expenseCard.comparisonText.contains("Jan'26"))
        #expect(presentation.incomeCard.comparisonText.contains("Jan'26"))
        // referenceDate == Feb 1, 2026 → no future bars (Mar'26) should be shown.
        #expect(presentation.bars.map { $0.label } == ["Nov'25", "Dec'25", "Jan'26", "Feb'26"])
    }

    @Test("Рост расходов помечается как негативный delta, падение расходов как позитивный")
    func expenseDeltaToneIsReversed() {
        let growthCard = CashflowInsightsChartBuilder.makePresentation(
            entries: [
                .init(id: "prev", date: Self.date(2026, 1, 10), income: 0, expense: 100),
                .init(id: "current", date: Self.date(2026, 2, 10), income: 0, expense: 160)
            ],
            granularity: .month,
            selectedPeriodStart: Self.date(2026, 2, 1),
            referenceDate: Self.date(2026, 2, 1),
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US")
        ).expenseCard

        let declineCard = CashflowInsightsChartBuilder.makePresentation(
            entries: [
                .init(id: "prev", date: Self.date(2026, 1, 10), income: 0, expense: 160),
                .init(id: "current", date: Self.date(2026, 2, 10), income: 0, expense: 100)
            ],
            granularity: .month,
            selectedPeriodStart: Self.date(2026, 2, 1),
            referenceDate: Self.date(2026, 2, 1),
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US")
        ).expenseCard

        #expect(growthCard.deltaTone == .negative)
        #expect(declineCard.deltaTone == .positive)
    }

    @Test("График по неделям использует начало недели и выделяет соседние периоды")
    func weeklyPresentationUsesWeekBuckets() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let selectedDate = calendar.date(from: DateComponents(weekday: 2, weekOfYear: 9, yearForWeekOfYear: 2026)) ?? Date()
        let selectedStart = CashflowInsightsChartBuilder.periodStart(
            for: selectedDate,
            granularity: .week,
            calendar: calendar
        )

        let presentation = CashflowInsightsChartBuilder.makePresentation(
            entries: [
                .init(id: "w8", date: calendar.date(byAdding: .day, value: -3, to: selectedStart) ?? selectedStart, income: 20, expense: 0),
                .init(id: "w9-exp", date: calendar.date(byAdding: .day, value: 1, to: selectedStart) ?? selectedStart, income: 0, expense: 50),
                .init(id: "w9-inc", date: calendar.date(byAdding: .day, value: 2, to: selectedStart) ?? selectedStart, income: 120, expense: 0)
            ],
            granularity: .week,
            selectedPeriodStart: selectedStart,
            referenceDate: selectedDate,
            calendar: calendar,
            locale: locale
        )

        // referenceDate belongs to week 9 → do not include future week 10.
        #expect(presentation.bars.map { $0.label } == ["W6", "W7", "W8", "W9"])
        #expect(abs(presentation.expenseCard.amount - 50) < 0.01)
        #expect(abs(presentation.incomeCard.amount - 120) < 0.01)
    }

    @Test("График не показывает периоды позже текущего referenceDate")
    func presentationClampsPeriodsToToday() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let referenceDate = Self.date(2026, 3, 8)

        let presentation = CashflowInsightsChartBuilder.makePresentation(
            entries: [],
            granularity: .year,
            selectedPeriodStart: Self.date(2031, 1, 1),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.selectedPeriodStart == Self.date(2026, 1, 1))
        #expect(presentation.bars.map { $0.label } == ["2023", "2024", "2025", "2026"])
    }

    @Test("Full screen график раскрывает всю историю до текущего периода")
    func fullScreenPresentationIncludesEntireHistory() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let referenceDate = Self.date(2026, 3, 8)

        let presentation = CashflowInsightsChartBuilder.makeFullScreenPresentation(
            entries: [
                .init(id: "2024", date: Self.date(2024, 1, 10), income: 300, expense: 0),
                .init(id: "2025", date: Self.date(2025, 6, 10), income: 0, expense: 120),
                .init(id: "2026", date: Self.date(2026, 3, 1), income: 80, expense: 40)
            ],
            granularity: .year,
            selectedPeriodStart: Self.date(2025, 1, 1),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.bars.map { $0.label } == ["2024", "2025", "2026"])
        #expect(presentation.selectedPeriodStart == Self.date(2025, 1, 1))
        #expect(abs(presentation.expenseCard.amount - 120) < 0.01)
    }

    @Test("Full screen график умеет ограничивать окно 12 периодами")
    func fullScreenPresentationSupportsTwelvePeriodsWindow() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let referenceDate = Self.date(2026, 3, 8)
        let entries = (1...20).map { monthOffset in
            CashflowConvertedTransaction(
                id: "\(monthOffset)",
                date: calendar.date(byAdding: .month, value: -monthOffset, to: referenceDate) ?? referenceDate,
                income: Double(monthOffset),
                expense: 0
            )
        }

        let presentation = CashflowInsightsChartBuilder.makeFullScreenPresentation(
            entries: entries,
            granularity: .month,
            selectedPeriodStart: Self.date(2026, 3, 1),
            referenceDate: referenceDate,
            maxVisiblePeriods: 12,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.bars.count == 12)
        #expect(presentation.bars.last?.label == "Mar'26")
    }

    @Test("Full screen график дополняет окно пустыми периодами слева, если истории мало")
    func fullScreenPresentationPadsMissingHistory() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let referenceDate = Self.date(2026, 3, 8)

        let presentation = CashflowInsightsChartBuilder.makeFullScreenPresentation(
            entries: [
                .init(id: "current", date: Self.date(2026, 3, 3), income: 100, expense: 0)
            ],
            granularity: .month,
            selectedPeriodStart: Self.date(2026, 3, 1),
            referenceDate: referenceDate,
            maxVisiblePeriods: 4,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.bars.count == 4)
        #expect(presentation.bars.last?.label == "Mar'26")
        #expect(presentation.bars.prefix(3).allSatisfy { $0.isPlaceholder })
    }

    @Test("Смещение selection стрелками зажимается в доступном диапазоне")
    func offsetSelectionClampsToAvailableRange() {
        let entries: [CashflowConvertedTransaction] = [
            .init(id: "2025", date: Self.date(2025, 2, 10), income: 0, expense: 50)
        ]

        let lower = CashflowInsightsChartBuilder.offsetSelection(
            Self.date(2025, 2, 1),
            by: -12,
            granularity: .month,
            entries: entries,
            referenceDate: Self.date(2026, 3, 8),
            calendar: Calendar(identifier: .gregorian)
        )
        let upper = CashflowInsightsChartBuilder.offsetSelection(
            Self.date(2025, 2, 1),
            by: 24,
            granularity: .month,
            entries: entries,
            referenceDate: Self.date(2026, 3, 8),
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(lower == Self.date(2025, 2, 1))
        #expect(upper == Self.date(2026, 3, 1))
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

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}
