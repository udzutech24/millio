//
//  FinanceOverviewChartModelsTests.swift
//  millioTests
//
//  Created by Codex on 08.03.2026.
//

import Foundation
import Testing
@testable import millio

struct FinanceOverviewChartModelsTests {
    @Test("Компактный обзор показывает только 4 последних периода")
    func compactPresentationShowsFourRecentPeriods() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let referenceDate = Self.date(2026, 3, 8)

        let presentation = FinanceOverviewChartBuilder.makePresentation(
            entries: [
                .init(id: Self.date(2025, 12, 1), date: Self.date(2025, 12, 1), debit: 20, credit: 5),
                .init(id: Self.date(2026, 1, 1), date: Self.date(2026, 1, 1), debit: 30, credit: 15),
                .init(id: Self.date(2026, 2, 1), date: Self.date(2026, 2, 1), debit: 40, credit: 10),
                .init(id: Self.date(2026, 3, 1), date: Self.date(2026, 3, 1), debit: 50, credit: 12)
            ],
            granularity: .month,
            selectedPeriodStart: Self.date(2026, 2, 1),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.bars.map(\.label) == ["Dec'25", "Jan'26", "Feb'26", "Mar'26"])
        #expect(presentation.selectedBar.label == "Feb'26")
        #expect(abs(presentation.selectedBar.saldo - 30) < 0.01)
    }

    @Test("Full screen обзор раскрывает всю историю без усечения")
    func fullScreenPresentationShowsEntireHistory() {
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        let referenceDate = Self.date(2026, 3, 8)

        let presentation = FinanceOverviewChartBuilder.makeFullScreenPresentation(
            entries: [
                .init(id: Self.date(2024, 1, 1), date: Self.date(2024, 1, 1), debit: 100, credit: 10),
                .init(id: Self.date(2025, 1, 1), date: Self.date(2025, 1, 1), debit: 30, credit: 60),
                .init(id: Self.date(2026, 1, 1), date: Self.date(2026, 1, 1), debit: 90, credit: 20)
            ],
            granularity: .year,
            selectedPeriodStart: Self.date(2025, 1, 1),
            referenceDate: referenceDate,
            calendar: calendar,
            locale: locale
        )

        #expect(presentation.bars.map(\.label) == ["2024", "2025", "2026"])
        #expect(presentation.selectedBar.label == "2025")
        #expect(abs(presentation.selectedBar.credit - 60) < 0.01)
        #expect(abs(presentation.selectedBar.saldo + 30) < 0.01)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        ) ?? Date()
    }
}
