import Foundation
import Testing
@testable import millio

@Suite("Deposit typed financial contract")
struct DepositFinancialContractTests {
    private let accountID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let opening = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z

    private var utc: DepositCalendarPolicy {
        DepositCalendarPolicy(timeZone: TimeZone(identifier: "UTC")!)
    }

    private func meta(
        rate: Decimal = 12,
        capitalization: AccountDepositCapitalization = .monthly,
        termEnd: Date? = nil,
        allowsTopUp: Bool = true,
        allowsEarlyClose: Bool = true
    ) -> DepositMeta {
        DepositMeta(
            rate: rate, capitalization: capitalization, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: allowsTopUp, allowsEarlyClose: allowsEarlyClose,
            earlyClosePenalty: nil, remindEnd: false, autoRollover: false
        )
    }

    private func event(
        id: UUID = UUID(),
        date: Date,
        createdAt: Date? = nil,
        type: AccountEventType,
        amount: Decimal,
        sourceID: String? = nil
    ) -> AccountEvent {
        AccountEvent(
            id: id, date: date, createdAt: createdAt ?? date,
            type: type, amount: amount, sourceTransactionID: sourceID
        )
    }

    private func generated(date: Date, amount: Decimal) -> AccountEvent {
        let key = utc.dayKey(for: date)
        return event(
            date: date, type: .interest, amount: amount,
            sourceID: DepositInterestScheduler.sourceTransactionID(accountID: accountID, dayKey: key)
        )
    }

    @Test("Confirmed, estimated-due and future interest remain separate")
    func separatesActualAndForecast() throws {
        let month1 = utc.monthAnniversary(1, after: opening)!
        let month2 = utc.monthAnniversary(2, after: opening)!
        let month3 = utc.monthAnniversary(3, after: opening)!
        let snapshot = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(termEnd: month3),
            events: [
                event(date: opening, type: .openingBalance, amount: 100_000),
                event(date: month1, type: .interest, amount: 900, sourceID: "bank:period-1"),
                generated(date: month2, amount: 1_010),
                generated(date: month3, amount: 1_020.10),
            ],
            asOf: month2, calendarPolicy: utc
        )

        #expect(snapshot.principal == .confirmed(100_000))
        #expect(snapshot.confirmedInterest == .confirmed(900))
        #expect(snapshot.estimatedDueInterest == .estimated(1_010))
        #expect(snapshot.futureInterest == .estimated(Decimal(string: "1020.10")!))
        #expect(snapshot.currentBalance == .confirmed(100_900))
        #expect(snapshot.projectedBalance == .estimated(Decimal(string: "102930.10")!))
        #expect(snapshot.maturityAmount == snapshot.projectedBalance)
        #expect(snapshot.nextAccrual?.date == month3)
    }

    @Test("Confirmed interest on a period replaces its generated estimate")
    func confirmedPeriodSuppressesGeneratedEstimate() {
        let payout = utc.monthAnniversary(1, after: opening)!
        let snapshot = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(termEnd: payout),
            events: [
                event(date: opening, type: .openingBalance, amount: 100_000),
                generated(date: payout, amount: 1_000),
                event(date: payout, createdAt: payout.addingTimeInterval(1), type: .interest, amount: 950, sourceID: "bank:confirmed")
            ],
            asOf: payout, calendarPolicy: utc
        )

        #expect(snapshot.confirmedInterest == .confirmed(950))
        #expect(snapshot.estimatedDueInterest == .unavailable)
        #expect(snapshot.currentBalance == .confirmed(100_950))
        #expect(snapshot.projectedBalance == .confirmed(100_950))
    }

    @Test("Current balance reuses AccountBalanceEngine over confirmed events")
    func currentBalanceMatchesSharedReplay() {
        let date = opening.addingTimeInterval(86_400)
        let actual = [
            event(date: opening, type: .openingBalance, amount: 1_000),
            event(date: date, type: .income, amount: 200),
            event(date: date, createdAt: date.addingTimeInterval(1), type: .fee, amount: 50),
        ]
        let snapshot = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(), events: actual, asOf: date, calendarPolicy: utc
        )

        #expect(snapshot.currentBalance.value == AccountBalanceEngine.balanceAt(
            events: actual, kind: .deposit, on: date
        ))
        #expect(snapshot.currentBalance == .confirmed(1_150))
        #expect(snapshot.principal == .confirmed(1_200))
    }

    @Test("Stable event ordering makes insertion order irrelevant")
    func insertionOrderDoesNotChangeSnapshot() {
        let date = opening.addingTimeInterval(86_400)
        let events = [
            event(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, date: date, type: .expense, amount: 100),
            event(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: opening, type: .openingBalance, amount: 1_000),
            event(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: date, type: .income, amount: 300),
        ]
        let forward = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(), events: events, asOf: date, calendarPolicy: utc
        )
        let reversed = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(), events: Array(events.reversed()), asOf: date, calendarPolicy: utc
        )

        #expect(forward == reversed)
    }

    @Test("Missing metadata never fabricates zero values")
    func missingMetadataIsTypedUnavailable() {
        let snapshot = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: nil,
            events: [event(date: opening, type: .openingBalance, amount: 100_000)],
            asOf: opening, calendarPolicy: utc
        )

        #expect(snapshot.lifecycleState == .incomplete)
        #expect(snapshot.currentBalance == .unavailable)
        #expect(snapshot.projectedBalance == .unavailable)
        #expect(snapshot.unresolved.contains(.missingMetadata))
    }

    @Test("Unsupported provider rules produce incomplete values")
    func unsupportedRulesAreExplicit() {
        let policy = DepositCalendarPolicy(
            timeZone: TimeZone(identifier: "UTC")!,
            dayCountConvention: .unsupported(reasonCode: "act_act")
        )
        let snapshot = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(),
            events: [event(date: opening, type: .openingBalance, amount: 100)],
            asOf: opening, calendarPolicy: policy, ratePolicy: .variableUnsupported
        )

        #expect(snapshot.lifecycleState == .incomplete)
        #expect(snapshot.currentBalance == .unavailable)
        #expect(snapshot.unresolved.contains(.unsupportedDayCountConvention))
        #expect(snapshot.unresolved.contains(.unsupportedVariableRate))
    }

    @Test("Zero/negative rates and corrupt interest are unavailable, not guessed", arguments: [Decimal.zero, -1])
    func invalidFinancialInputs(rate: Decimal) {
        let snapshot = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(rate: rate),
            events: [
                event(date: opening, type: .openingBalance, amount: 100),
                event(date: opening, type: .interest, amount: -1)
            ],
            asOf: opening, calendarPolicy: utc
        )

        #expect(snapshot.currentBalance == .unavailable)
        #expect(snapshot.unresolved.contains(.invalidRate))
        #expect(snapshot.unresolved.contains(.invalidEventAmount))
    }

    @Test("Lifecycle and progress are derived without persisted state")
    func lifecycleDerivation() {
        let maturity = utc.monthAnniversary(3, after: opening)!
        let openingSnapshot = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(termEnd: maturity), events: [], asOf: opening, calendarPolicy: utc
        )
        let dueSoonDate = maturity.addingTimeInterval(-10 * 86_400)
        let dueSoon = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(termEnd: maturity), events: [], asOf: dueSoonDate, calendarPolicy: utc
        )
        let matured = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(termEnd: maturity), events: [], asOf: maturity, calendarPolicy: utc
        )
        let closed = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            archivedAt: dueSoonDate, meta: meta(termEnd: maturity), events: [],
            asOf: maturity, calendarPolicy: utc
        )

        #expect(openingSnapshot.lifecycleState == .active)
        #expect(openingSnapshot.progress == 0)
        #expect(dueSoon.lifecycleState == .dueSoon)
        #expect(matured.lifecycleState == .maturedNeedsAction)
        #expect(matured.progress == 1)
        #expect(matured.capabilities.allowsTopUp == false)
        #expect(matured.capabilities.allowsEarlyClose == false)
        #expect(closed.lifecycleState == .closed)
        #expect(closed.capabilities.allowsTopUp == false)
    }

    @Test("Calendar policy keeps month anniversaries local through DST")
    func localMonthAnniversaryAcrossDST() {
        for identifier in ["UTC", "Europe/Istanbul", "America/Los_Angeles"] {
            let policy = DepositCalendarPolicy(timeZone: TimeZone(identifier: identifier)!)
            let localOpening = policy.calendar.date(from: DateComponents(year: 2025, month: 2, day: 28))!
            let anniversary = policy.monthAnniversary(1, after: localOpening)!
            #expect(policy.dayKey(for: anniversary) == "2025-03-28")
        }
    }

    @Test("Withdrawal amount is unavailable until a product policy exists")
    func withdrawalDoesNotGuessAvailability() {
        let snapshot = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(allowsEarlyClose: true),
            events: [event(date: opening, type: .openingBalance, amount: 100_000)],
            asOf: opening, calendarPolicy: utc
        )

        #expect(snapshot.availableToWithdraw == .unavailable)
        #expect(snapshot.capabilities.allowsWithdrawal == false)
        #expect(snapshot.unresolved.contains(.unsupportedWithdrawalPolicy))
    }

    @Test("Missing generated schedule never becomes a zero forecast")
    func missingScheduleIsUnavailable() {
        let maturity = utc.monthAnniversary(3, after: opening)!
        let snapshot = DepositFinancialContract.snapshot(
            accountID: accountID, currency: "RUB", openingDate: opening,
            meta: meta(termEnd: maturity),
            events: [event(date: opening, type: .openingBalance, amount: 100_000)],
            asOf: opening, calendarPolicy: utc
        )

        #expect(snapshot.currentBalance == .confirmed(100_000))
        #expect(snapshot.estimatedDueInterest == .unavailable)
        #expect(snapshot.futureInterest == .unavailable)
        #expect(snapshot.projectedBalance == .unavailable)
        #expect(snapshot.unresolved.contains(.missingGeneratedSchedule))
    }
}
