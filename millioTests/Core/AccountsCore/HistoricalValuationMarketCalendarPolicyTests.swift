import Foundation
import Testing
@testable import millio

@Suite("Historical valuation market calendars")
struct HistoricalValuationMarketCalendarPolicyTests {
    private let fiat = HistoricalValuationCalendarPolicy.fiat(
        id: "cbr-rub-v1",
        holidays: ["2026-01-01", "2026-01-02", "2026-01-05", "2026-01-06", "2026-01-07"]
    )

    @Test
    func weekendAndDeclaredHolidayCanUseTheImmediatelyPrecedingOpenClose() {
        #expect(fiat.allowsPreviousClose(from: "2026-01-09", for: "2026-01-10"))
        #expect(fiat.allowsPreviousClose(from: "2025-12-31", for: "2026-01-01"))
        #expect(fiat.allowsPreviousClose(from: "2025-12-31", for: "2026-01-07"))
    }

    @Test
    func anOpenWeekdayMissOrSkippedOpenDayCannotBeForwardFilled() {
        #expect(!fiat.allowsPreviousClose(from: "2026-01-12", for: "2026-01-13"))
        #expect(!fiat.allowsPreviousClose(from: "2026-01-09", for: "2026-01-14"))
    }

    @Test
    func exchangePolicyUsesItsOwnWeekdaysAndHolidaySet() {
        let exchange = HistoricalValuationCalendarPolicy.exchange(
            id: "moex-v1",
            openWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            holidays: ["2026-05-01"]
        )

        #expect(exchange.allowsPreviousClose(from: "2026-04-30", for: "2026-05-01"))
        #expect(!exchange.allowsPreviousClose(from: "2026-04-30", for: "2026-05-04"))
    }

    @Test
    func crypto24x7NeverInventsAPreviousDailyCloseForAMissingDay() {
        let crypto = HistoricalValuationCalendarPolicy.crypto24x7(id: "crypto-utc-v1")

        #expect(!crypto.allowsPreviousClose(from: "2026-01-09", for: "2026-01-10"))
        #expect(!crypto.allowsPreviousClose(from: "2026-01-10", for: "2026-01-11"))
    }

    @Test
    func malformedOrUnboundedDatesAreRejected() {
        #expect(!fiat.allowsPreviousClose(from: "bad", for: "2026-01-10"))
        #expect(!fiat.allowsPreviousClose(from: "2026-01-10", for: "2026-01-10"))
        #expect(!fiat.allowsPreviousClose(from: "2025-01-01", for: "2026-01-01"))
    }
}
