import Foundation
import Testing
@testable import millio

/// Ф2 кредита: расчётное ядро против эталонных чисел спеки §4.5.
///
/// Кредит 1 200 000 ₽ · 18,9% годовых · 60 месяцев · аннуитет. Все 12 контрольных чисел сходятся
/// В НОЛЬ только при неокруглённом платеже (контракт §4.3): с округлённым до рубля платежом
/// остаток после 5 платежей уезжает на 2 ₽, а переплата — на 20 ₽.
@Suite("LoanScheduleEngine")
struct LoanScheduleEngineTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var firstPayment: Date {
        calendar.date(from: DateComponents(year: 2025, month: 2, day: 10))!
    }

    private func referenceTerms(
        frequency: LoanPaymentFrequency = .monthly,
        scheduleType: LoanScheduleType = .annuity
    ) -> LoanTerms {
        LoanTerms(
            principal: 1_200_000,
            annualRatePercent: 18.9,
            termPeriods: 60 / frequency.stepMonths,
            firstPaymentDate: firstPayment,
            scheduleType: scheduleType,
            frequency: frequency
        )
    }

    /// Округление ТОЛЬКО на сравнении — ровно так же, как оно живёт в UI.
    private func rubles(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var mutable = value
        NSDecimalRound(&result, &mutable, 0, .plain)
        return result
    }

    // MARK: - Эталонные числа §4.5

    @Test("Платёж эталонного кредита — 31 063 ₽")
    func annuityPaymentMatchesReference() {
        let terms = referenceTerms()
        let payment = LoanScheduleEngine.annuityPayment(
            principal: terms.principal,
            periodRate: LoanScheduleEngine.periodRate(annualRatePercent: 18.9, frequency: .monthly),
            periods: 60
        )
        #expect(rubles(payment) == 31_063)
    }

    @Test("После 5 платежей: остаток 1 137 241, тело 62 759, проценты 92 554")
    func stateAfterFivePaymentsMatchesReference() {
        let schedule = LoanScheduleEngine.schedule(terms: referenceTerms(), calendar: calendar)
        #expect(schedule.paymentCount == 60)

        let paidPrincipal = schedule.rows.prefix(5).reduce(Decimal.zero) { $0 + $1.principal }
        let paidInterest = schedule.rows.prefix(5).reduce(Decimal.zero) { $0 + $1.interest }

        #expect(rubles(schedule.outstandingPrincipal(afterPayments: 5)) == 1_137_241)
        #expect(rubles(paidPrincipal) == 62_759)
        #expect(rubles(paidInterest) == 92_554)
    }

    @Test("Шестой платёж: проценты 17 912, тело 13 151")
    func sixthPaymentSplitMatchesReference() {
        let schedule = LoanScheduleEngine.schedule(terms: referenceTerms(), calendar: calendar)
        let row = schedule.rows[5]
        #expect(rubles(row.interest) == 17_912)
        #expect(rubles(row.principal) == 13_151)
    }

    @Test("Переплата за срок — 663 760 ₽, проценты впереди после 5 платежей — 571 206 ₽")
    func overpaymentAndInterestAheadMatchReference() {
        let schedule = LoanScheduleEngine.schedule(terms: referenceTerms(), calendar: calendar)
        #expect(rubles(schedule.totalOverpayment) == 663_760)
        #expect(rubles(schedule.interestAhead(afterPayments: 5)) == 571_206)
    }

    @Test("Квартальная периодичность: платёж 94 059 ₽, переплата 681 174 ₽")
    func quarterlyFrequencyMatchesReference() {
        let terms = referenceTerms(frequency: .quarterly)
        let schedule = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
        #expect(schedule.paymentCount == 20)
        #expect(rubles(schedule.rows[0].payment) == 94_059)
        #expect(rubles(schedule.totalOverpayment) == 681_174)
    }

    @Test("Полугодовая периодичность: платёж 190 704 ₽, переплата 707 041 ₽")
    func semiannualFrequencyMatchesReference() {
        let terms = referenceTerms(frequency: .semiannual)
        let schedule = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
        #expect(schedule.paymentCount == 10)
        #expect(rubles(schedule.rows[0].payment) == 190_704)
        #expect(rubles(schedule.totalOverpayment) == 707_041)
    }

    // MARK: - Контракт округления

    @Test("Округлённый платёж НЕ даёт эталонных чисел — округляем только на отображении")
    func roundedPaymentBreaksReferenceNumbers() {
        var terms = referenceTerms()
        terms.paymentOverride = 31_063  // тот же платёж, но округлённый до рубля
        let schedule = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)

        // Разница мелкая, но систематическая — ровно то, из-за чего контракт §4.3 обязателен.
        #expect(rubles(schedule.outstandingPrincipal(afterPayments: 5)) == 1_137_239)
        #expect(rubles(schedule.totalOverpayment) != 663_760)
    }

    // MARK: - Дифференцированный график

    @Test("Дифференцированный: сумма тел = principal, платёж убывает, остаток сходится в ноль")
    func differentiatedScheduleInvariants() {
        let schedule = LoanScheduleEngine.schedule(
            terms: referenceTerms(scheduleType: .differentiated), calendar: calendar
        )
        #expect(schedule.paymentCount == 60)

        let principalSum = schedule.rows.reduce(Decimal.zero) { $0 + $1.principal }
        #expect(principalSum == 1_200_000)
        #expect(schedule.rows.last?.balanceAfter == .zero)

        let payments = schedule.rows.map(\.payment)
        #expect(zip(payments, payments.dropFirst()).allSatisfy { $0 > $1 })
        // Первый платёж = 20 000 тела + 18 900 процентов на полную сумму.
        #expect(rubles(payments[0]) == 38_900)
    }

    // MARK: - Даты и периодичность

    @Test("Даты периодов идут шагом периодичности от первого платежа")
    func paymentDatesFollowFrequencyStep() {
        let schedule = LoanScheduleEngine.schedule(terms: referenceTerms(frequency: .quarterly), calendar: calendar)
        #expect(schedule.rows[0].date == firstPayment)
        #expect(schedule.rows[1].date == calendar.date(from: DateComponents(year: 2025, month: 5, day: 10)))
        #expect(schedule.payoffDate == calendar.date(from: DateComponents(year: 2029, month: 11, day: 10)))
    }

    @Test("Платёж 31-го числа не пропускает короткие месяцы, а прижимается к последнему дню")
    func paymentDatesClampShortMonths() {
        var terms = referenceTerms()
        terms.firstPaymentDate = calendar.date(from: DateComponents(year: 2025, month: 1, day: 31))!
        let schedule = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
        #expect(schedule.rows[1].date == calendar.date(from: DateComponents(year: 2025, month: 2, day: 28)))
        #expect(schedule.rows[2].date == calendar.date(from: DateComponents(year: 2025, month: 3, day: 31)))
    }

    // MARK: - Граничные случаи

    @Test("Платёж ниже процентов первого периода = долг не гасится, график пуст")
    func paymentBelowInterestDoesNotAmortize() {
        var terms = referenceTerms()
        terms.paymentOverride = 1_000  // проценты первого периода — 18 900 ₽
        let schedule = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
        #expect(schedule.rows.isEmpty)
        #expect(schedule.amortizes == false)
    }

    @Test("Ручной платёж выше расчётного сокращает срок, последний платёж — неполный")
    func paymentOverrideRecalculatesTerm() {
        var terms = referenceTerms()
        terms.paymentOverride = 40_000
        let schedule = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
        #expect(schedule.paymentCount < 60)
        #expect(schedule.rows.last?.balanceAfter == .zero)
        #expect((schedule.rows.last?.payment ?? 0) <= 40_000)
    }

    @Test("Нулевая ставка: тело делится поровну, переплаты нет")
    func zeroRateSplitsPrincipalEvenly() {
        var terms = referenceTerms()
        terms.annualRatePercent = 0
        let schedule = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
        #expect(schedule.paymentCount == 60)
        #expect(schedule.totalOverpayment == .zero)
        #expect(schedule.rows[0].payment == 20_000)
    }

    @Test("Пустые условия (нулевая сумма или нулевой срок) дают пустой график, а не крэш")
    func degenerateTermsProduceEmptySchedule() {
        var zeroPrincipal = referenceTerms()
        zeroPrincipal.principal = 0
        #expect(LoanScheduleEngine.schedule(terms: zeroPrincipal, calendar: calendar).rows.isEmpty)

        var zeroTerm = referenceTerms()
        zeroTerm.termPeriods = 0
        #expect(LoanScheduleEngine.schedule(terms: zeroTerm, calendar: calendar).rows.isEmpty)
    }

    @Test("Периодичность: шаг в месяцах и число периодов в году")
    func frequencyStepsAreConsistent() {
        #expect(LoanPaymentFrequency.allCases.map(\.stepMonths) == [1, 2, 3, 6, 12])
        #expect(LoanPaymentFrequency.allCases.map(\.periodsPerYear) == [12, 6, 4, 2, 1])
    }
}
