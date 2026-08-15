import Foundation
import Testing
@testable import millio

@Suite("Credit-card payment calendar policy")
struct CreditCardPaymentPolicyTests {
    private func calendar(timeZone: String = "UTC") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: timeZone)!
        return result
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test("Grace days cross month end using calendar days")
    func graceAcrossShortMonth() throws {
        let cal = calendar()
        var settings = CreditCardPaymentSettings()
        settings.mode = .gracePeriod
        settings.anchorDate = date(2028, 1, 31, calendar: cal)
        let due = try #require(CreditCardPaymentPolicy.dueDate(settings: settings, graceDays: 30, calendar: cal))
        #expect(cal.dateComponents([.year, .month, .day], from: due) == DateComponents(year: 2028, month: 3, day: 1))
    }

    @Test("Exact payment date is not reinterpreted through grace days")
    func exactDateWins() throws {
        let cal = calendar()
        var settings = CreditCardPaymentSettings()
        settings.mode = .exactDate
        settings.exactDate = date(2026, 2, 28, calendar: cal)
        let due = try #require(CreditCardPaymentPolicy.dueDate(settings: settings, graceDays: 55, calendar: cal))
        #expect(cal.component(.day, from: due) == 28)
    }

    @Test("Status is deterministic in the injected timezone")
    func overdueAndRemaining() throws {
        let cal = calendar(timeZone: "Europe/Istanbul")
        var settings = CreditCardPaymentSettings()
        settings.mode = .exactDate
        settings.exactDate = date(2026, 8, 10, calendar: cal)
        let before = try #require(CreditCardPaymentPolicy.status(
            settings: settings, graceDays: nil, now: date(2026, 8, 7, calendar: cal), calendar: cal
        ))
        let after = try #require(CreditCardPaymentPolicy.status(
            settings: settings, graceDays: nil, now: date(2026, 8, 12, calendar: cal), calendar: cal
        ))
        #expect(before.daysRemaining == 3 && !before.isOverdue)
        #expect(after.daysRemaining == -2 && after.isOverdue)
    }

    @Test("Reminder supports the typed lead options")
    func reminderLead() throws {
        let cal = calendar()
        var settings = CreditCardPaymentSettings()
        settings.mode = .exactDate
        settings.exactDate = date(2026, 8, 10, calendar: cal)
        settings.reminderLead = .threeDays
        settings.reminderHour = 9
        settings.reminderMinute = 30
        let reminder = try #require(CreditCardPaymentPolicy.reminderDate(
            settings: settings, graceDays: nil, calendar: cal
        ))
        let components = cal.dateComponents([.day, .hour, .minute], from: reminder)
        #expect(components.day == 7 && components.hour == 9 && components.minute == 30)
    }

    @Test("Missing grace terms produce an honest empty state")
    func missingTerms() {
        var settings = CreditCardPaymentSettings()
        settings.mode = .gracePeriod
        #expect(CreditCardPaymentPolicy.status(
            settings: settings, graceDays: nil, now: Date(), calendar: calendar()
        ) == nil)
    }
}
