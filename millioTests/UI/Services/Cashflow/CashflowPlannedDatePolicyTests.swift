import Foundation
import Testing
@testable import millio

@Suite("CashflowPlannedDatePolicy")
struct CashflowPlannedDatePolicyTests {
    @Test("Today is actual at every time; tomorrow is planned", arguments: [
        "Europe/Istanbul", "America/Los_Angeles", "Asia/Shanghai"
    ])
    func calendarDayBoundary(timeZoneID: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZoneID))
        let policy = CashflowPlannedDatePolicy(calendar: calendar)
        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12)))

        for components in [
            DateComponents(year: 2026, month: 8, day: 14, hour: 0, minute: 1),
            DateComponents(year: 2026, month: 8, day: 14, hour: 10, minute: 39),
            DateComponents(year: 2026, month: 8, day: 14, hour: 23, minute: 59)
        ] {
            let today = try #require(calendar.date(from: components))
            #expect(!policy.isOneTimePlanned(today, relativeTo: reference))
        }

        let tomorrow = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 15)))
        #expect(policy.isOneTimePlanned(tomorrow, relativeTo: reference))
    }
}
