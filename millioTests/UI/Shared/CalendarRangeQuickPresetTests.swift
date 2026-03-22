import Foundation
import Testing
@testable import millio

struct CalendarRangeQuickPresetTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("Last 7 days preset includes today and the previous 6 full days")
    func last7DaysRangeIsInclusive() {
        let reference = makeDate(year: 2026, month: 3, day: 22)

        let range = CalendarRangeQuickPreset.last7Days.dateRange(
            referenceDate: reference,
            calendar: calendar
        )

        #expect(range.start == makeDate(year: 2026, month: 3, day: 16))
        #expect(range.end == reference)
    }

    @Test("This month preset starts at the beginning of the current month")
    func thisMonthStartsAtMonthBoundary() {
        let reference = makeDate(year: 2026, month: 3, day: 22)

        let range = CalendarRangeQuickPreset.thisMonth.dateRange(
            referenceDate: reference,
            calendar: calendar
        )

        #expect(range.start == makeDate(year: 2026, month: 3, day: 1))
        #expect(range.end == reference)
    }

    @Test("Year to date preset starts on January 1st of the current year")
    func yearToDateStartsAtYearBoundary() {
        let reference = makeDate(year: 2026, month: 8, day: 9)

        let range = CalendarRangeQuickPreset.yearToDate.dateRange(
            referenceDate: reference,
            calendar: calendar
        )

        #expect(range.start == makeDate(year: 2026, month: 1, day: 1))
        #expect(range.end == reference)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
