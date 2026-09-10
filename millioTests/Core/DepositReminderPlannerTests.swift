import Foundation
import Testing
@testable import millio

@Suite("Deposit maturity reminder planner")
struct DepositReminderPlannerTests {
    private let accountID = UUID(uuidString: "0A0A0A0A-1B1B-2C2C-3D3D-4E4E4E4E4E4E")!
    private let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z

    private func meta(termEnd: Date?, remindEnd: Bool) -> DepositMeta {
        DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: nil,
            remindEnd: remindEnd, autoRollover: false
        )
    }

    private func request(_ meta: DepositMeta?) -> DepositMaturityReminderRequest? {
        DepositReminderPlanner.request(
            accountID: accountID, accountName: "Вклад в банке", meta: meta, now: now
        )
    }

    @Test("Накопительный счёт (termEnd == nil) уведомления не получает")
    func openEndedDepositGetsNoReminder() {
        #expect(request(meta(termEnd: nil, remindEnd: true)) == nil)
    }

    @Test("Напоминание выключено — запроса нет")
    func reminderDisabled() {
        #expect(request(meta(termEnd: now.addingTimeInterval(30 * 86_400), remindEnd: false)) == nil)
    }

    @Test("Срок уже прошёл — напоминать не о чем")
    func pastMaturityGetsNoReminder() {
        #expect(request(meta(termEnd: now.addingTimeInterval(-86_400), remindEnd: true)) == nil)
    }

    @Test("Условий нет — запроса нет")
    func missingMetaGetsNoReminder() {
        #expect(request(nil) == nil)
    }

    @Test("Срок в будущем и напоминание включено — запрос с датой окончания")
    func futureMaturityProducesRequest() throws {
        let maturity = now.addingTimeInterval(30 * 86_400)
        let result = try #require(request(meta(termEnd: maturity, remindEnd: true)))

        #expect(result == DepositMaturityReminderRequest(
            accountID: accountID, accountName: "Вклад в банке", maturityDate: maturity
        ))
    }
}
