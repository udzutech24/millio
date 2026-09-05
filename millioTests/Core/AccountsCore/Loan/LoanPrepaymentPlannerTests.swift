import Foundation
import Testing
@testable import millio

/// Ф2 + Ф6 кредита: досрочное погашение и недоплата против эталонных чисел спеки §4.5.
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

    /// Остаток берётся из графика договора — на месте `AccountDetailView` его даёт лента событий,
    /// и после первой же досрочки эти величины расходятся (спека Р6). Планировщик поэтому
    /// принимает остаток параметром, а не выводит его сам.
    private func outstanding(_ terms: LoanTerms, afterPayments count: Int) -> Decimal {
        LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
            .outstandingPrincipal(afterPayments: count)
    }

    private func plan(
        _ terms: LoanTerms, paymentsMade: Int = 5, amount: Decimal
    ) -> LoanPrepaymentPlan? {
        LoanPrepaymentPlanner.plan(
            terms: terms,
            outstandingPrincipal: outstanding(terms, afterPayments: paymentsMade),
            paymentsMade: paymentsMade,
            amount: amount,
            calendar: calendar
        )
    }

    private func rubles(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var mutable = value
        NSDecimalRound(&result, &mutable, 0, .plain)
        return result
    }

    // MARK: - Эталонный сценарий макета

    @Test("Досрочно 200 000 ₽ → «платёж»: новый платёж 25 600 ₽, экономия 100 455 ₽")
    func prepaymentReducingPaymentMatchesReference() throws {
        let plan = try #require(self.plan(terms, amount: 200_000))
        #expect(rubles(plan.balanceBefore) == 1_137_241)
        #expect(rubles(plan.balanceAfter) == 937_241)
        #expect(plan.baselineRemainingPayments == 55)

        let payment = try #require(plan.payment)
        #expect(rubles(payment.payment) == 25_600)
        #expect(payment.remainingPayments == 55)
        #expect(payment.paymentsDelta == 0)
        #expect(rubles(payment.savings) == 100_455)
    }

    @Test("Досрочно 200 000 ₽ → «срок»: 42 платежа вместо 55, экономия 226 771 ₽")
    func prepaymentReducingTermMatchesReference() throws {
        let plan = try #require(self.plan(terms, amount: 200_000))
        #expect(plan.term.remainingPayments == 42)
        #expect(plan.term.paymentsDelta == -13)
        #expect(rubles(plan.term.payment) == 31_063)
        #expect(rubles(plan.term.savings) == 226_771)
        // Оба сценария стартуют от одного и того же нового остатка — иначе сравнение в листе врёт.
        #expect(rubles(plan.baselineInterestAhead) == 571_206)
        #expect(rubles(plan.baselinePayment) == 31_063)
    }

    @Test("Подтверждение записывает всю сумму в тело и закрепляет выбранный платёж")
    func entryCarriesStrategyToTheLedger() throws {
        let plan = try #require(self.plan(terms, amount: 200_000))

        let term = try #require(plan.entry(for: .term))
        #expect(term.principalPart == plan.appliedAmount)
        #expect(rubles(plan.appliedAmount) == 200_000)
        #expect(term.interestPart == .zero)
        // Досрочка не занимает период: «ближайший платёж останется прежним».
        #expect(term.consumesPeriod == false)
        // Платёж закрепляется и на «сроке»: без этого пересчёт от нового остатка вернул бы
        // 55 платежей по 25 600 ₽, то есть молча подменил бы сценарий.
        #expect(rubles(try #require(term.pinnedPayment)) == 31_063)

        let payment = try #require(plan.entry(for: .payment))
        #expect(rubles(try #require(payment.pinnedPayment)) == 25_600)
    }

    /// Вход `plan` — доплата СВЕРХ графика, каким бы маленьким ни был её размер: она целиком уходит
    /// в тело, поэтому число платежей не меняется, а выгода просто мельче. Заниженный очередной
    /// платёж — другой сценарий, он разбирается в `evaluate`/`underpayment`.
    @Test("Маленькая доплата сверх графика: срок прежний, выгода мельче, но положительная")
    func smallTopUpStillReducesDebt() throws {
        let plan = try #require(self.plan(terms, amount: 10_000))
        #expect(plan.term.remainingPayments == 55)
        #expect(plan.term.paymentsDelta == 0)
        #expect(rubles(plan.term.savings) == 13_620)
        #expect(rubles(try #require(plan.payment).payment) == 30_790)
        #expect(rubles(try #require(plan.payment).savings) == 5_023)
    }

    @Test("Досрочка больше остатка закрывает кредит: платежей ноль, экономия = все проценты впереди")
    func fullPrepaymentClosesLoan() throws {
        let plan = try #require(self.plan(terms, amount: 2_000_000))
        #expect(plan.balanceAfter == .zero)
        #expect(plan.closesLoan)
        #expect(plan.term.remainingPayments == 0)
        // Выбирать нечего: сценарий «платёж» при полном погашении не существует.
        #expect(plan.payment == nil)
        #expect(rubles(plan.term.savings) == 571_206)
        #expect(plan.term.paymentsDelta == -55)
        // Спишется ровно остаток, а не введённая сумма: иначе долг ушёл бы в плюс.
        #expect(rubles(plan.appliedAmount) == 1_137_241)
        let entry = try #require(plan.entry(for: .term))
        #expect(rubles(entry.principalPart) == 1_137_241)
        #expect(entry.pinnedPayment == nil)
    }

    @Test("Бессмысленные входы дают nil, а не выдуманный план")
    func invalidInputsReturnNil() {
        #expect(plan(terms, amount: 0) == nil)
        #expect(plan(terms, paymentsMade: 60, amount: 100_000) == nil)
    }

    // MARK: - Дифференцированный график (Ф6)

    private var differentiatedTerms: LoanTerms {
        var result = terms
        result.scheduleType = .differentiated
        return result
    }

    @Test("Дифференцированный: сценарий «срок» есть, «платёж» — нет")
    func differentiatedPlansTermOnly() throws {
        let plan = try #require(self.plan(differentiatedTerms, amount: 200_000))

        #expect(rubles(plan.balanceBefore) == 1_100_000)
        #expect(rubles(plan.balanceAfter) == 900_000)
        #expect(plan.baselineRemainingPayments == 55)
        // Тело в периоде постоянно (20 000 ₽), поэтому 200 000 ₽ убирают ровно 10 периодов.
        #expect(plan.term.remainingPayments == 45)
        #expect(plan.term.paymentsDelta == -10)
        #expect(rubles(plan.term.savings) == 159_075)
        // «Платёж» для убывающего платежа не определён (спека §10) — сценарий один.
        #expect(plan.payment == nil)
        // Закреплять в договоре нечего: число периодов пересчитывается от остатка.
        #expect(try #require(plan.entry(for: .term)).pinnedPayment == nil)
        #expect(plan.entry(for: .payment) == nil)
    }

    @Test("Дифференцированный: платёж в листе — ближайший, он падает вслед за остатком")
    func differentiatedShowsNearestPayment() throws {
        let plan = try #require(self.plan(differentiatedTerms, amount: 200_000))
        #expect(rubles(plan.baselinePayment) == 37_325)
        #expect(rubles(plan.term.payment) == 34_175)
    }

    // MARK: - Недоплата (Ф6)

    private func underpayment(_ terms: LoanTerms, amount: Decimal) -> LoanUnderpaymentPlan? {
        LoanPrepaymentPlanner.underpayment(
            terms: terms,
            outstandingPrincipal: outstanding(terms, afterPayments: 5),
            paymentsMade: 5,
            amount: amount,
            calendar: calendar
        )
    }

    @Test("Недоплата 25 000 ₽: проценты периода первыми, в тело 7 088 ₽, срок +1 платёж")
    func underpaymentCoversInterestFirst() throws {
        let plan = try #require(underpayment(terms, amount: 25_000))

        #expect(rubles(plan.interestPart) == 17_912)
        #expect(rubles(plan.principalPart) == 7_088)
        #expect(rubles(plan.balanceAfter) == 1_130_152)
        #expect(plan.paymentsDelta == 1)
        #expect(rubles(plan.extraInterest) == 8_257)
        // Платёж дальше прежний — недоплата его не пересчитывает, она удлиняет срок.
        #expect(rubles(plan.scheduledPayment) == 31_063)
        #expect(rubles(try #require(plan.pinnedPayment)) == 31_063)
        #expect(plan.entry.consumesPeriod)
    }

    @Test("Недоплата ниже процентов периода: тело не уменьшается, переплата растёт на всю сумму")
    func underpaymentBelowInterestLeavesPrincipal() throws {
        let plan = try #require(underpayment(terms, amount: 10_000))

        #expect(rubles(plan.periodInterest) == 17_912)
        #expect(rubles(plan.interestPart) == 10_000)
        #expect(plan.principalPart == .zero)
        #expect(plan.balanceAfter == plan.balanceBefore)
        #expect(plan.paymentsDelta == 1)
        // Заплатили 10 000 ₽ процентов и не сдвинули долг — ровно на эту сумму выросла переплата.
        #expect(rubles(plan.extraInterest) == 10_000)
        // В ленту писать нечего: тела в операции нет.
        #expect(plan.entry.principalPart == .zero)
    }

    @Test("Граница «недоплата / досрочка» — ближайший плановый платёж")
    func evaluateSplitsByScheduledPayment() throws {
        func evaluate(_ amount: Decimal) -> LoanExtraPayment? {
            LoanPrepaymentPlanner.evaluate(
                terms: terms, outstandingPrincipal: outstanding(terms, afterPayments: 5),
                paymentsMade: 5, amount: amount, calendar: calendar
            )
        }

        guard case .underpayment = try #require(evaluate(31_000)) else {
            Issue.record("Сумма ниже планового платежа обязана уходить в недоплату")
            return
        }
        guard case .prepayment = try #require(evaluate(31_100)) else {
            Issue.record("Сумма выше планового платежа — доплата сверх графика")
            return
        }
        #expect(evaluate(0) == nil)
    }
}
