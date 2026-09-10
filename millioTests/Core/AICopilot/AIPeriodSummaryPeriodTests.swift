import Foundation
import XCTest
@testable import millio

/// Период итогов держится ЛОКАЛЬНО (Ф1b, риск 2): общий `CashflowInsightsGranularity`
/// расширять кварталом нельзя — он задаёт ось всех графиков кэшфлоу.
final class AIPeriodSummaryPeriodTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Риск 2: общий enum не тронут

    func testCashflowInsightsGranularityStillHasNoQuarter() {
        XCTAssertEqual(
            CashflowInsightsGranularity.allCases.map(\.rawValue),
            ["year", "month", "week"],
            "Квартал должен жить в AIPeriodKind, а не в общей гранулярности графиков"
        )
    }

    func testAIPeriodKindCarriesQuarterLocally() {
        XCTAssertEqual(AIPeriodKind.allCases.map(\.rawValue), ["month", "quarter"])
    }

    // MARK: - Границы месяца

    func testMonthStartsOnFirstDayAndEndsAtCalendarEnd() {
        let period = AIPeriodSummaryPeriod(kind: .month, anchor: date(2026, 9, 17))
        XCTAssertEqual(period.start(calendar: calendar), date(2026, 9, 1))
        XCTAssertEqual(period.calendarEnd(calendar: calendar), date(2026, 9, 30))
    }

    func testCurrentMonthRangeIsClampedToToday() {
        let now = date(2026, 9, 10)
        let period = AIPeriodSummaryPeriod(kind: .month, anchor: now)
        let range = period.effectiveRange(now: now, calendar: calendar)
        XCTAssertEqual(range.lowerBound, date(2026, 9, 1))
        XCTAssertEqual(range.upperBound, date(2026, 9, 10))
    }

    func testPastMonthRangeIsNotClamped() {
        let period = AIPeriodSummaryPeriod(kind: .month, anchor: date(2026, 7, 4))
        let range = period.effectiveRange(now: date(2026, 9, 10), calendar: calendar)
        XCTAssertEqual(range.lowerBound, date(2026, 7, 1))
        XCTAssertEqual(range.upperBound, date(2026, 7, 31))
    }

    // MARK: - Границы квартала

    func testQuarterCoversThreeCalendarMonths() {
        let period = AIPeriodSummaryPeriod(kind: .quarter, anchor: date(2026, 9, 17))
        XCTAssertEqual(period.start(calendar: calendar), date(2026, 7, 1))
        XCTAssertEqual(period.calendarEnd(calendar: calendar), date(2026, 9, 30))
        XCTAssertEqual(
            period.months(calendar: calendar),
            [date(2026, 7, 1), date(2026, 8, 1), date(2026, 9, 1)]
        )
    }

    func testEveryMonthMapsToItsQuarter() {
        let expectedStarts = [1, 1, 1, 4, 4, 4, 7, 7, 7, 10, 10, 10]
        for month in 1...12 {
            let period = AIPeriodSummaryPeriod(kind: .quarter, anchor: date(2026, month, 15))
            XCTAssertEqual(
                period.start(calendar: calendar),
                date(2026, expectedStarts[month - 1], 1),
                "Месяц \(month) попал не в свой квартал"
            )
        }
    }

    func testMonthPeriodCoversOneMonthOnly() {
        let period = AIPeriodSummaryPeriod(kind: .month, anchor: date(2026, 9, 17))
        XCTAssertEqual(period.months(calendar: calendar), [date(2026, 9, 1)])
    }

    // MARK: - Предыдущий период

    func testPreviousRangeIsSameLengthWindowRightBefore() {
        let now = date(2026, 9, 10)
        let period = AIPeriodSummaryPeriod(kind: .month, anchor: now)
        let previous = period.previousRange(now: now, calendar: calendar)
        // Текущее окно 1–10 сентября = 10 дней, значит предыдущее — 22–31 августа.
        XCTAssertEqual(previous.lowerBound, date(2026, 8, 22))
        XCTAssertEqual(previous.upperBound, date(2026, 8, 31))
    }

    func testPreviousQuarterRangeIsSameLengthWindow() {
        let now = date(2026, 9, 30)
        let period = AIPeriodSummaryPeriod(kind: .quarter, anchor: now)
        let current = period.effectiveRange(now: now, calendar: calendar)
        let previous = period.previousRange(now: now, calendar: calendar)
        XCTAssertEqual(previous.upperBound, date(2026, 6, 30))
        let currentDays = calendar.dateComponents([.day], from: current.lowerBound, to: current.upperBound).day
        let previousDays = calendar.dateComponents([.day], from: previous.lowerBound, to: previous.upperBound).day
        XCTAssertEqual(currentDays, previousDays)
    }

    func testFirstDayOfMonthStillProducesNonEmptyRanges() {
        let now = date(2026, 9, 1)
        let period = AIPeriodSummaryPeriod(kind: .month, anchor: now)
        let range = period.effectiveRange(now: now, calendar: calendar)
        XCTAssertEqual(range.lowerBound, range.upperBound)
        let previous = period.previousRange(now: now, calendar: calendar)
        XCTAssertEqual(previous.lowerBound, date(2026, 8, 31))
        XCTAssertEqual(previous.upperBound, date(2026, 8, 31))
    }
}
