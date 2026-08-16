import Foundation
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct AppleCalendarEventExportTests {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int = 2026, _ month: Int = 8, _ day: Int, hour: Int = 12) -> Date {
        let calendar = utcCalendar()
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    @Test("Calendar export permits only future planner dates")
    func eligibilityRejectsDueAndPastDates() {
        let calendar = utcCalendar()
        let now = date(2026, 8, 16, hour: 15)

        #expect(!AppleCalendarEventExportEligibility.isEligible(
            scheduledDate: date(2026, 8, 15), now: now, calendar: calendar
        ))
        #expect(!AppleCalendarEventExportEligibility.isEligible(
            scheduledDate: date(2026, 8, 16, hour: 23), now: now, calendar: calendar
        ))
        #expect(AppleCalendarEventExportEligibility.isEligible(
            scheduledDate: date(2026, 8, 17), now: now, calendar: calendar
        ))
    }

    @Test("Payload uses a 09:00 local event with an exact fifteen-minute duration")
    func payloadMapsDateAndNormalizesNotes() throws {
        let calendar = utcCalendar()
        let payload = try #require(AppleCalendarEventExportPayloadBuilder(calendar: calendar).makePayload(
            title: "Planned expense",
            notes: "  Internet bill  ",
            scheduledDate: date(2026, 8, 20)
        ))

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: payload.startDate)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 20)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
        #expect(payload.endDate.timeIntervalSince(payload.startDate) == 15 * 60)
        #expect(payload.notes == "Internet bill")
        #expect(payload.timeZone == calendar.timeZone)
    }

    @Test("Payload drops an empty optional note")
    func payloadDropsEmptyNotes() throws {
        let payload = try #require(AppleCalendarEventExportPayloadBuilder(calendar: utcCalendar()).makePayload(
            title: "Planned income", notes: " \n ", scheduledDate: date(2026, 8, 20)
        ))
        #expect(payload.notes == nil)
    }

    @Test("Credit-card export uses the canonical future due date and configured reminder time")
    func creditCardPayloadUsesPaymentSettings() throws {
        let calendar = utcCalendar()
        var settings = CreditCardPaymentSettings()
        settings.reminderHour = 11
        settings.reminderMinute = 30
        let payload = try #require(CreditCardCalendarPaymentExport(
            calendar: calendar,
            now: { self.date(2026, 8, 16) },
            locale: Locale(identifier: "en_US")
        ).makePayload(
            cardName: "Alfa Credit",
            paymentStatus: .init(dueDate: date(2026, 10, 4), daysRemaining: 49, isOverdue: false),
            settings: settings,
            minimumPayment: 12_500,
            currency: "RUB"
        ))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: payload.startDate)
        #expect(components.year == 2026)
        #expect(components.month == 10)
        #expect(components.day == 4)
        #expect(components.hour == 11)
        #expect(components.minute == 30)
        #expect(payload.title == "Alfa Credit")
        #expect(payload.notes == "12,500 RUB")
    }

    @Test("Credit-card export rejects due and overdue payments and never infers a payment amount")
    func creditCardPayloadRejectsPastDateAndOmitsUnknownAmount() throws {
        let calendar = utcCalendar()
        var settings = CreditCardPaymentSettings()
        settings.reminderHour = 99
        settings.reminderMinute = -5
        let exporter = CreditCardCalendarPaymentExport(calendar: calendar, now: { self.date(2026, 8, 16) })

        #expect(exporter.makePayload(
            cardName: "Card",
            paymentStatus: .init(dueDate: date(2026, 8, 16), daysRemaining: 0, isOverdue: false),
            settings: settings,
            minimumPayment: nil,
            currency: "RUB"
        ) == nil)

        let future = try #require(exporter.makePayload(
            cardName: "Card",
            paymentStatus: .init(dueDate: date(2026, 8, 20), daysRemaining: 4, isOverdue: false),
            settings: settings,
            minimumPayment: nil,
            currency: "RUB"
        ))
        let components = calendar.dateComponents([.hour, .minute], from: future.startDate)
        #expect(components.hour == 23)
        #expect(components.minute == 0)
        #expect(future.notes == nil)
    }

    @Test("Authorizer does not request permission when the existing state is terminal")
    func authorizerPreservesExistingAuthorizationState() async {
        let denied = FakeAppleCalendarEventStore(state: .denied)
        let authorizer = AppleCalendarEventExportAuthorizer(eventStore: denied)

        #expect(await authorizer.authorizeForExport() == .denied)
        #expect(denied.requestCount == 0)
    }

    @Test("Authorizer requests write-only permission once when needed")
    func authorizerRequestsUndeterminedPermission() async {
        let store = FakeAppleCalendarEventStore(state: .notDetermined, requestResult: true)
        let authorizer = AppleCalendarEventExportAuthorizer(eventStore: store)

        #expect(await authorizer.authorizeForExport() == .granted)
        #expect(store.requestCount == 1)
    }
}

@MainActor
private final class FakeAppleCalendarEventStore: AppleCalendarEventStoreProtocol {
    var state: AppleCalendarAuthorizationState
    let requestResult: Bool
    private(set) var requestCount = 0

    init(state: AppleCalendarAuthorizationState, requestResult: Bool = false) {
        self.state = state
        self.requestResult = requestResult
    }

    var authorizationState: AppleCalendarAuthorizationState { state }

    func requestWriteOnlyAccess() async throws -> Bool {
        requestCount += 1
        if requestResult {
            state = .granted
        }
        return requestResult
    }
}
