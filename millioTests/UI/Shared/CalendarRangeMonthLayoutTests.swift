import Foundation
import Testing
@testable import millio

struct CalendarRangeMonthLayoutTests {
    @Test("Calendar range layout keeps only days of the target month")
    func daysInMonthDoNotLeakIntoNextMonth() {
        let calendar = Calendar(identifier: .gregorian)
        let march2026 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)) ?? Date()

        let days = CalendarRangeMonthLayout.daysInMonth(for: march2026, calendar: calendar)

        #expect(days.count == 31)
        #expect(calendar.component(.month, from: days.first ?? march2026) == 3)
        #expect(calendar.component(.month, from: days.last ?? march2026) == 3)
    }

    @Test("Calendar range layout uses Monday as the first column")
    func leadingPlaceholderCountMatchesMondayFirstGrid() {
        let calendar = Calendar(identifier: .gregorian)
        let marchStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()

        let leading = CalendarRangeMonthLayout.leadingPlaceholderCount(for: marchStart, calendar: calendar)

        #expect(leading == 6)
    }

    @Test("Calendar range weekday symbols are rotated to Monday-first order")
    func weekdaySymbolsStartWithMonday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let symbols = CalendarRangeMonthLayout.orderedWeekdaySymbols(calendar: calendar)

        #expect(symbols.count == 7)
        #expect(symbols.first == "Mon")
        #expect(symbols.last == "Sun")
    }
}
