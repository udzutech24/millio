import Foundation
import Testing
@testable import millio

@Suite("Deposit nudge engine")
struct DepositNudgeEngineTests {
    private let accountID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let opening = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z
    private let day: TimeInterval = 86_400

    private var utc: DepositCalendarPolicy {
        DepositCalendarPolicy(timeZone: TimeZone(identifier: "UTC")!)
    }

    private func meta(
        termEnd: Date?,
        remindEnd: Bool = true,
        autoRollover: Bool = false
    ) -> DepositMeta {
        DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: nil,
            remindEnd: remindEnd, autoRollover: autoRollover
        )
    }

    private func snapshot(
        lifecycle: DepositLifecycleState,
        asOf: Date,
        maturityDate: Date?,
        daysRemaining: Int?
    ) -> DepositPresentationSnapshot {
        DepositPresentationSnapshot(
            asOf: asOf, currency: "RUB", principal: .confirmed(100_000),
            confirmedInterest: .confirmed(5_000), estimatedDueInterest: .estimated(0),
            futureInterest: .estimated(0), currentBalance: .confirmed(105_000),
            projectedBalance: .estimated(105_000), availableToWithdraw: .unavailable,
            nextAccrual: nil, maturityDate: maturityDate, maturityAmount: .estimated(105_000),
            daysRemaining: daysRemaining, progress: nil, lifecycleState: lifecycle,
            capabilities: .init(
                allowsTopUp: false, allowsEarlyClose: false, allowsWithdrawal: false,
                reminderIsOperational: false, autoRolloverIsOperational: false
            ),
            unresolved: []
        )
    }

    // MARK: - Накопительный счёт (termEnd == nil)

    @Test("Накопительный счёт без срока не получает ни одной подсказки")
    func openEndedProducesNoNudges() {
        let asOf = opening.addingTimeInterval(200 * day)
        let result = DepositNudgeEngine.nudges(
            snapshot: snapshot(lifecycle: .openEnded, asOf: asOf, maturityDate: nil, daysRemaining: nil),
            meta: meta(termEnd: nil, remindEnd: true, autoRollover: true),
            calendarPolicy: utc
        )
        #expect(result.isEmpty)
    }

    @Test("Сквозная проверка: вклад без termEnd остаётся openEnded и молчит")
    func openEndedThroughFinancialContract() {
        let asOf = opening.addingTimeInterval(90 * day)
        let contractSnapshot = DepositFinancialContract.snapshot(
            accountID: accountID,
            currency: "RUB",
            openingDate: opening,
            meta: meta(termEnd: nil),
            events: [AccountEvent(
                id: UUID(), date: opening, createdAt: opening,
                type: .openingBalance, amount: 100_000, sourceTransactionID: nil
            )],
            asOf: asOf,
            calendarPolicy: utc
        )

        #expect(contractSnapshot.lifecycleState == .openEnded)
        #expect(DepositNudgeEngine.nudges(
            snapshot: contractSnapshot, meta: meta(termEnd: nil), calendarPolicy: utc
        ).isEmpty)
    }

    // MARK: - Молчащие состояния

    @Test("Без условий, до окна 30 дней и после закрытия подсказок нет")
    func silentStates() {
        let asOf = opening.addingTimeInterval(10 * day)
        let maturity = opening.addingTimeInterval(300 * day)
        let active = snapshot(lifecycle: .active, asOf: asOf, maturityDate: maturity, daysRemaining: 290)

        #expect(DepositNudgeEngine.nudges(snapshot: active, meta: nil, calendarPolicy: utc).isEmpty)
        #expect(DepositNudgeEngine.nudges(
            snapshot: active, meta: meta(termEnd: maturity, remindEnd: false, autoRollover: true),
            calendarPolicy: utc
        ).isEmpty)
        for lifecycle in [DepositLifecycleState.closed, .incomplete] {
            #expect(DepositNudgeEngine.nudges(
                snapshot: snapshot(lifecycle: lifecycle, asOf: asOf, maturityDate: maturity, daysRemaining: 290),
                meta: meta(termEnd: maturity),
                calendarPolicy: utc
            ).isEmpty)
        }
    }

    // MARK: - Скоро конец срока

    @Test("В окне 30 дней подсказка несёт остаток дней из снапшота")
    func dueSoonReportsDaysRemaining() {
        let asOf = opening.addingTimeInterval(288 * day)
        let maturity = opening.addingTimeInterval(300 * day)
        let result = DepositNudgeEngine.nudges(
            snapshot: snapshot(lifecycle: .dueSoon, asOf: asOf, maturityDate: maturity, daysRemaining: 12),
            meta: meta(termEnd: maturity),
            calendarPolicy: utc
        )

        #expect(result == [.maturityApproaching(daysRemaining: 12)])
    }

    @Test("Выключенное напоминание и включённая пролонгация добавляют свои подсказки")
    func dueSoonAddsReminderAndRolloverNudges() {
        let asOf = opening.addingTimeInterval(288 * day)
        let maturity = opening.addingTimeInterval(300 * day)
        let result = DepositNudgeEngine.nudges(
            snapshot: snapshot(lifecycle: .dueSoon, asOf: asOf, maturityDate: maturity, daysRemaining: 12),
            meta: meta(termEnd: maturity, remindEnd: false, autoRollover: true),
            calendarPolicy: utc
        )

        #expect(result == [.maturityApproaching(daysRemaining: 12), .rolloverIsManual, .reminderOff])
    }

    // MARK: - Срок вышел

    @Test("После срока считаем дни ОТ даты окончания, а не клэмпнутый остаток")
    func maturedCountsDaysSinceMaturity() {
        let maturity = opening.addingTimeInterval(300 * day)
        let asOf = maturity.addingTimeInterval(3 * day)
        let result = DepositNudgeEngine.nudges(
            // daysRemaining после срока всегда 0 — движок обязан взять число из своей формулы.
            snapshot: snapshot(lifecycle: .maturedNeedsAction, asOf: asOf, maturityDate: maturity, daysRemaining: 0),
            meta: meta(termEnd: maturity),
            calendarPolicy: utc
        )

        #expect(result == [.maturedNeedsAction(daysSinceMaturity: 3)])
    }

    @Test("В день окончания срока подсказка без числа дней")
    func maturedTodayHasZeroDays() {
        let maturity = opening.addingTimeInterval(300 * day)
        let result = DepositNudgeEngine.nudges(
            snapshot: snapshot(
                lifecycle: .maturedNeedsAction, asOf: maturity, maturityDate: maturity, daysRemaining: 0
            ),
            meta: meta(termEnd: maturity),
            calendarPolicy: utc
        )

        #expect(result == [.maturedNeedsAction(daysSinceMaturity: 0)])
    }

    @Test("После срока напоминание уже не предлагаем, а про пролонгацию говорим")
    func maturedNeverSuggestsReminder() {
        let maturity = opening.addingTimeInterval(300 * day)
        let asOf = maturity.addingTimeInterval(day)
        let result = DepositNudgeEngine.nudges(
            snapshot: snapshot(
                lifecycle: .maturedNeedsAction, asOf: asOf, maturityDate: maturity, daysRemaining: 0
            ),
            meta: meta(termEnd: maturity, remindEnd: false, autoRollover: true),
            calendarPolicy: utc
        )

        #expect(result == [.maturedNeedsAction(daysSinceMaturity: 1), .rolloverIsManual])
        #expect(!result.contains(.reminderOff))
    }
}
