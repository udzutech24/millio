import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф7 кредита, критерий приёмки 5: net worth уменьшается ровно на ОСТАТОК ТЕЛА долга, а будущие
/// проценты в него не попадают (спека Р6). Правок `AccountTotalsContribution` для этого не нужно —
/// тест обязан это доказать, а не постулировать: `.loan` уже отдаёт баланс ленты со своим знаком,
/// а лента содержит только тело.
@Suite(.serialized)
@MainActor
struct LoanNetWorthContributionTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func rubles(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal.zero
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }

    /// Эталонный кредит спеки §4.5: 1 200 000 ₽ · 18,9% · 60 мес · аннуитет · ежемесячно.
    private func referenceTerms() -> LoanTerms {
        LoanTerms(
            principal: 1_200_000,
            annualRatePercent: 18.9,
            termPeriods: 60,
            firstPaymentDate: day(2026, 4, 15),
            scheduleType: .annuity,
            frequency: .monthly
        )
    }

    @Test("Пять платежей: тотал падает на 1 137 241 ₽, будущие проценты 571 206 ₽ в него не входят")
    func loanReducesTotalByOutstandingPrincipalOnly() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let openDate = day(2026, 3, 15)
        let paymentDate = day(2026, 8, 15)

        _ = try service.createAccount(
            name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 2_000_000, date: openDate
        )
        let loan = try service.createAccount(
            name: "Автокредит", kind: .loan, currency: "RUB", openingBalance: 1_200_000,
            loanMeta: LoanMeta(
                principal: 1_200_000, rate: 18.9, monthlyPayment: nil, paymentDay: 15,
                termEnd: nil, scheduleType: .annuity, insurance: nil
            ),
            date: openDate
        )

        // Пять платежей по графику — ровно тот сценарий, на котором посчитаны эталонные числа.
        let schedule = LoanScheduleEngine.schedule(terms: referenceTerms(), calendar: calendar)
        let paidRows = schedule.rows.prefix(5)
        let paidPrincipal = paidRows.reduce(Decimal.zero) { $0 + $1.principal }
        let paidInterest = paidRows.reduce(Decimal.zero) { $0 + $1.interest }
        try LoanPaymentRecorder(modelContext: context).recordScheduledPayment(
            account: loan, principalPart: paidPrincipal, interestPart: paidInterest, date: paymentDate
        )

        let outstanding = schedule.outstandingPrincipal(afterPayments: 5)
        let interestAhead = schedule.interestAhead(afterPayments: 5)
        #expect(rubles(outstanding) == 1_137_241)
        #expect(rubles(interestAhead) == 571_206)

        let totals = AccountsTotalsService(
            modelContext: context,
            rebuilder: AccountSnapshotRebuilder(modelContainer: container),
            rateService: DateAwareMockRateService()
        )
        let total = await totals.totalAt(paymentDate, in: "RUB")

        // Долг входит в сальдо минусом ровно на тело: 2 000 000 − 1 137 241.
        #expect(rubles(total) == 862_759)
        // И не на тело + будущие проценты: если бы график попадал в тотал, здесь было бы 291 553.
        #expect(rubles(total) != rubles(2_000_000 - outstanding - interestAhead))
    }

    @Test("Уплаченные проценты долг не гасят: тотал не растёт на 92 554 ₽")
    func paidInterestDoesNotImproveNetWorth() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let paymentDate = day(2026, 8, 15)

        let loan = try service.createAccount(
            name: "Автокредит", kind: .loan, currency: "RUB", openingBalance: 1_200_000,
            loanMeta: LoanMeta(
                principal: 1_200_000, rate: 18.9, monthlyPayment: nil, paymentDay: 15,
                termEnd: nil, scheduleType: .annuity, insurance: nil
            ),
            date: day(2026, 3, 15)
        )
        try LoanPaymentRecorder(modelContext: context).recordScheduledPayment(
            account: loan, principalPart: 13_151, interestPart: 17_912, date: paymentDate
        )

        let totals = AccountsTotalsService(
            modelContext: context,
            rebuilder: AccountSnapshotRebuilder(modelContainer: container),
            rateService: DateAwareMockRateService()
        )
        let total = await totals.totalAt(paymentDate, in: "RUB")

        // Платёж 31 063 ₽ улучшил сальдо только на тело 13 151 ₽ — проценты ушли безвозвратно.
        #expect(rubles(total) == -1_186_849)
    }
}
