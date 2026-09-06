import Foundation
import Testing
@testable import millio

struct CashflowEntryHistoryStatusPolicyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test("Actual operations are always paid")
    func actualIsPaid() {
        #expect(CashflowEntryHistoryStatusPolicy.status(
            for: .actual(date: date(day: 4)),
            calendar: calendar
        ) == .paid)
    }

    @Test("One-time plan is paid only after its effect was applied")
    func oneTimePlanRequiresAppliedEffect() {
        #expect(CashflowEntryHistoryStatusPolicy.status(
            for: .oneTimePlan(date: date(day: 4), hasAppliedEffect: false),
            calendar: calendar
        ) == .upcoming)
        #expect(CashflowEntryHistoryStatusPolicy.status(
            for: .oneTimePlan(date: date(day: 4), hasAppliedEffect: true),
            calendar: calendar
        ) == .paid)
    }

    @Test("Recurring occurrence links by series, type, and calendar day")
    func recurringLinkIsExact() {
        let item = CashflowEntryHistoryStatusPolicy.Item.recurringOccurrence(
            date: date(day: 5, hour: 8),
            recurrenceSeriesID: "salary",
            transactionTypeRaw: "income"
        )
        let exact = CashflowEntryHistoryStatusPolicy.CompletedOccurrence(
            recurrenceSeriesID: "salary",
            transactionTypeRaw: "income",
            date: date(day: 5, hour: 20)
        )
        #expect(CashflowEntryHistoryStatusPolicy.status(
            for: item,
            completedOccurrences: [exact],
            calendar: calendar
        ) == .paid)

        let wrongType = CashflowEntryHistoryStatusPolicy.CompletedOccurrence(
            recurrenceSeriesID: "salary",
            transactionTypeRaw: "expense",
            date: date(day: 5, hour: 20)
        )
        let wrongDay = CashflowEntryHistoryStatusPolicy.CompletedOccurrence(
            recurrenceSeriesID: "salary",
            transactionTypeRaw: "income",
            date: date(day: 6)
        )
        #expect(CashflowEntryHistoryStatusPolicy.status(
            for: item,
            completedOccurrences: [wrongType, wrongDay],
            calendar: calendar
        ) == .upcoming)
    }

    private func date(day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }
}
