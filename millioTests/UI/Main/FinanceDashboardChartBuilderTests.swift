import Foundation
import Testing
@testable import millio

struct FinanceDashboardChartBuilderTests {
    @Test("Finance dashboard starts with one-week period")
    func defaultPeriodIsWeek() {
        #expect(FinanceDashboardChartBuilder.defaultPeriod == .week)
        #expect(FinanceDashboardPeriodOption.defaultOption == .week)
    }

    @Test("Week chart keeps chronological points and daily stride")
    func weeklyChartUsesDailyStride() {
        let output = FinanceDashboardChartBuilder.makeOutput(
            points: [
                .init(date: Self.date(2026, 4, 4), value: 22000, label: "Total"),
                .init(date: Self.date(2026, 4, 1), value: 12000, label: "Total"),
                .init(date: Self.date(2026, 4, 3), value: 21000, label: "Total")
            ],
            period: .week
        )

        #expect(output.points.map(\.date) == [
            Self.date(2026, 4, 1),
            Self.date(2026, 4, 3),
            Self.date(2026, 4, 4)
        ])
        #expect(output.xAxisStride == .day)
        #expect(output.xAxisCount == 7)
    }

    @Test("All-period chart switches to monthly stride")
    func allPeriodChartUsesMonthlyStride() {
        let output = FinanceDashboardChartBuilder.makeOutput(
            points: [
                .init(date: Self.date(2025, 1, 1), value: 1000, label: "Total"),
                .init(date: Self.date(2026, 4, 4), value: 23000, label: "Total")
            ],
            period: .all
        )

        #expect(output.xAxisStride == .month)
        #expect(output.xAxisCount == 5)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        ) ?? Date()
    }
}
