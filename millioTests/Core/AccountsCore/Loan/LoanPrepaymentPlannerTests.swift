import Foundation
import Testing
@testable import millio

/// Ф2 кредита: досрочное погашение против эталонных чисел спеки §4.5.
///
/// Сценарий макета: после 5 платежей по эталонному кредиту вносим 200 000 ₽ сверху.
/// Экономия считается по ФАКТИЧЕСКОМУ графику — закрытая формула даёт 226 817 ₽ вместо 226 771 ₽.
@Suite("LoanPrepaymentPlanner")
struct LoanPrepaymentPlannerTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var terms: LoanTerms {
        LoanTerms(
            principal: 1_200_000,
            annualRatePercent: 18.9,
            termPeriods: 60,
            firstPaymentDate: calendar.date(from: DateComponents(year: 2025, month: 2, day: 10))!,
            scheduleType: .annuity,
            frequency: .monthly
        )
    }

    private func rubles(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var mutable = value
        NSDecimalRound(&result, &mutable, 0, .plain)
        return result
    }

    @Test("Досрочно 200 000 ₽ → «платёж»: новый платёж 25 600 ₽, экономия 100 455 ₽")
    func prepaymentReducingPaymentMatchesReference() throws {
        let plan = try #require(
            LoanPrepaymentPlanner.plan(terms: terms, paymentsMade: 5, amount: 200_000, calendar: calendar)
        )
        #expect(rubles(plan.balanceBefore) == 1_137_241)
        #expect(rubles(plan.balanceAfter) == 937_241)
        #expect(plan.baselineRemainingPayments == 55)

        #expect(rubles(plan.payment.payment) == 25_600)
        #expect(plan.payment.remainingPayments == 55)
        #expect(plan.payment.paymentsDelta == 0)
        #expect(rubles(plan.payment.savings) == 100_455)
    }

    @Test("Досрочно 200 000 ₽ → «срок»: 42 платежа вместо 55, экономия 226 771 ₽")
    func prepaymentReducingTermMatchesReference() throws {
        let plan = try #require(
            LoanPrepaymentPlanner.plan(terms: terms, paymentsMade: 5, amount: 200_000, calendar: calendar)
        )
        #expect(plan.term.remainingPayments == 42)
        #expect(plan.term.paymentsDelta == -13)
        #expect(rubles(plan.term.payment) == 31_063)
        #expect(rubles(plan.term.savings) == 226_771)
        // Оба сценария стартуют от одного и того же нового остатка — иначе сравнение в листе врёт.
        #expect(rubles(plan.baselineInterestAhead) == 571_206)
    }

    /// Сумма меньше планового платежа («недоплата» из §4.4) — валидный вход: она целиком уходит в
    /// тело, поэтому число платежей не меняется, а выгода просто мельче. Срок здесь НЕ растёт:
    /// вход планировщика — доплата сверх графика, а не заниженный очередной платёж (иначе
    /// эталонный остаток был бы 955 153 ₽ вместо 937 241 ₽ — реального сценария макета).
    @Test("Сумма меньше планового платежа: срок прежний, выгода мельче, но положительная")
    func amountBelowRegularPaymentStillReducesDebt() throws {
        let plan = try #require(
            LoanPrepaymentPlanner.plan(terms: terms, paymentsMade: 5, amount: 10_000, calendar: calendar)
        )
        #expect(plan.term.remainingPayments == 55)
        #expect(plan.term.paymentsDelta == 0)
        #expect(rubles(plan.term.savings) == 13_620)
        #expect(rubles(plan.payment.payment) == 30_790)
        #expect(rubles(plan.payment.savings) == 5_023)
    }

    /// Заниженный очередной платёж — это другой сценарий: он живёт в `paymentOverride`, и если
    /// платёж не покрывает процентов, долг не гасится вовсе. Лист досрочки такой ввод показывать
    /// не должен — график пустой, считать нечего.
    @Test("Платёж ниже процентов периода долг не гасит — график пустой")
    func paymentBelowInterestNeverAmortizes() {
        var underpaid = terms
        underpaid.paymentOverride = 15_000
        #expect(LoanScheduleEngine.schedule(terms: underpaid, calendar: calendar).amortizes == false)
    }

    @Test("Досрочка больше остатка закрывает кредит: платежей ноль, экономия = все проценты впереди")
    func fullPrepaymentClosesLoan() throws {
        let plan = try #require(
            LoanPrepaymentPlanner.plan(terms: terms, paymentsMade: 5, amount: 2_000_000, calendar: calendar)
        )
        #expect(plan.balanceAfter == .zero)
        #expect(plan.term.remainingPayments == 0)
        #expect(plan.payment.remainingPayments == 0)
        #expect(rubles(plan.term.savings) == 571_206)
        #expect(plan.term.paymentsDelta == -55)
    }

    @Test("Бессмысленные входы дают nil, а не выдуманный план")
    func invalidInputsReturnNil() {
        #expect(LoanPrepaymentPlanner.plan(terms: terms, paymentsMade: 5, amount: 0, calendar: calendar) == nil)
        #expect(LoanPrepaymentPlanner.plan(terms: terms, paymentsMade: 60, amount: 100_000, calendar: calendar) == nil)

        // Дифференцированный график пока не поддержан: «сократить платёж» для него не определено
        // (платёж убывает сам по себе), спека §10.
        var differentiated = terms
        differentiated.scheduleType = .differentiated
        #expect(LoanPrepaymentPlanner.plan(terms: differentiated, paymentsMade: 5, amount: 200_000, calendar: calendar) == nil)
    }
}
