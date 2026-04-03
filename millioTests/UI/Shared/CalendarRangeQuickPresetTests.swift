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

    @Test("Calendar range copy is localized for English, Russian, and Simplified Chinese")
    func localizedTitles() {
        #expect(CalendarRangeQuickPreset.today.title(locale: Locale(identifier: "en_US")) == "Today")
        #expect(CalendarRangeQuickPreset.thisMonth.title(locale: Locale(identifier: "ru_RU")) == "Этот месяц")
        #expect(CalendarRangeQuickPreset.yearToDate.title(locale: Locale(identifier: "zh_Hans_CN")) == "今年至今")
        #expect(CalendarRangePickerCopy.sheetTitle(locale: Locale(identifier: "zh_Hans_CN")) == "选择时间范围")
        #expect(CalendarRangePickerCopy.startDateLabel(locale: Locale(identifier: "ru_RU")) == "Дата начала")
        #expect(CalendarRangePickerCopy.endDateLabel(locale: Locale(identifier: "en_US")) == "End date")
    }

    @Test("Calendar range date labels format against the app locale instead of device locale")
    func endpointDateFormattingUsesRequestedLocale() {
        let date = makeDate(year: 2026, month: 4, day: 1)

        #expect(CalendarRangeFormatting.endpointDate(date, locale: Locale(identifier: "en_US")) == "1 April")
        #expect(CalendarRangeFormatting.endpointDate(date, locale: Locale(identifier: "ru_RU")) == "1 апреля")
        #expect(CalendarRangeFormatting.endpointDate(date, locale: Locale(identifier: "zh_Hans_CN")) == "4月1日")
    }

    @Test("Calendar range month title uses the app locale for month names")
    func monthTitleUsesRequestedLocale() {
        let date = makeDate(year: 2026, month: 4, day: 1)

        #expect(CalendarRangeFormatting.monthTitle(for: date, locale: Locale(identifier: "en_US")) == "April 2026")
        #expect(CalendarRangeFormatting.monthTitle(for: date, locale: Locale(identifier: "ru_RU")) == "Апрель 2026")
        #expect(CalendarRangeFormatting.monthTitle(for: date, locale: Locale(identifier: "zh_Hans_CN")) == "2026年4月")
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
