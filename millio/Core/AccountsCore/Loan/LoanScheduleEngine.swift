import Foundation

/// Строка графика погашения: один платёж по кредиту.
struct LoanScheduleRow: Equatable, Sendable {
    /// Номер платежа с единицы — тот же индекс, что видит пользователь в графике.
    let index: Int
    let date: Date
    let payment: Decimal
    let interest: Decimal
    let principal: Decimal
    let balanceAfter: Decimal
}

/// График погашения целиком плюс производные величины (переплата, проценты впереди, дата закрытия).
///
/// Все величины считаются по ФАКТИЧЕСКОМУ графику, а не по закрытым формулам: экономия от
/// досрочного погашения по формуле и по графику расходятся на сотни рублей (спека §4.4).
struct LoanSchedule: Equatable, Sendable {
    /// Тело долга на старте графика — нужен для `outstandingPrincipal(afterPayments: 0)`,
    /// когда строк ещё не «пройдено».
    let principal: Decimal
    let rows: [LoanScheduleRow]

    /// Пустой график = платёж не покрывает даже проценты первого периода: долг не гасится никогда.
    var amortizes: Bool { !rows.isEmpty }

    var paymentCount: Int { rows.count }

    var totalOverpayment: Decimal { rows.reduce(Decimal.zero) { $0 + $1.interest } }

    var payoffDate: Date? { rows.last?.date }

    /// Остаток тела долга после `count` внесённых платежей.
    func outstandingPrincipal(afterPayments count: Int) -> Decimal {
        guard count > 0 else { return principal }
        guard count < rows.count else { return .zero }
        return rows[count - 1].balanceAfter
    }

    /// Проценты, которые ещё предстоит заплатить, если платить строго по графику.
    func interestAhead(afterPayments count: Int) -> Decimal {
        rows.dropFirst(max(0, count)).reduce(Decimal.zero) { $0 + $1.interest }
    }

    func nextPaymentDate(afterPayments count: Int) -> Date? {
        let index = max(0, count)
        return index < rows.count ? rows[index].date : nil
    }
}

/// Расчётное ядро кредита: чистые функции, никакого SwiftData и никакого UI.
///
/// ⚠️ Контракт округления (спека §4.3): всё считается в `Decimal` БЕЗ промежуточных округлений,
/// платёж не округляется. Округление до рубля/копейки — только на отображении
/// (`DepositInterestScheduler.round2`). С округлённым платежом эталонные числа расходятся
/// на 2–20 ₽ — это проверено расчётом, а не вкусовщина.
enum LoanScheduleEngine {

    /// Потолок строк для графика с ручным платежом: срок в нём не задан договором, и платёж чуть
    /// выше процентов растянул бы цикл на тысячи итераций. 1200 периодов = 100 лет при месячном шаге.
    static let maxOpenEndedPeriods = 1200

    static func periodRate(annualRatePercent: Decimal, frequency: LoanPaymentFrequency) -> Decimal {
        annualRatePercent / 100 / Decimal(frequency.periodsPerYear)
    }

    /// Аннуитет: `P·i·(1+i)^n / ((1+i)^n − 1)`. Результат НЕ округляется — см. контракт выше.
    static func annuityPayment(principal: Decimal, periodRate: Decimal, periods: Int) -> Decimal {
        guard periods > 0, principal > 0 else { return .zero }
        guard periodRate > 0 else { return principal / Decimal(periods) }
        let growth = pow(1 + periodRate, periods)
        return principal * periodRate * growth / (growth - 1)
    }

    /// Регулярный платёж по условиям: ручной, если задан, иначе расчётный аннуитет.
    /// Для дифференцированного графика регулярного платежа не существует — он убывает.
    static func regularPayment(terms: LoanTerms) -> Decimal? {
        guard terms.scheduleType == .annuity else { return nil }
        if let override = terms.paymentOverride { return override }
        return annuityPayment(
            principal: terms.principal,
            periodRate: periodRate(annualRatePercent: terms.annualRatePercent, frequency: terms.frequency),
            periods: terms.termPeriods
        )
    }

    static func schedule(terms: LoanTerms, calendar: Calendar = Calendar(identifier: .gregorian)) -> LoanSchedule {
        let principal = max(terms.principal, .zero)
        guard principal > 0 else { return LoanSchedule(principal: principal, rows: []) }
        let rate = periodRate(annualRatePercent: terms.annualRatePercent, frequency: terms.frequency)

        switch terms.scheduleType {
        case .annuity:
            return annuitySchedule(terms: terms, principal: principal, periodRate: rate, calendar: calendar)
        case .differentiated:
            return differentiatedSchedule(terms: terms, principal: principal, periodRate: rate, calendar: calendar)
        }
    }

    // MARK: - Аннуитет

    private static func annuitySchedule(
        terms: LoanTerms,
        principal: Decimal,
        periodRate rate: Decimal,
        calendar: Calendar
    ) -> LoanSchedule {
        // Ручной платёж не задан → срок фиксирован договором. Задан → срок пересчитывается под него
        // (число строк — пока остаток > 0), спека §4.2.
        let hasFixedTerm = terms.paymentOverride == nil
        let limit = hasFixedTerm ? terms.termPeriods : maxOpenEndedPeriods
        guard limit > 0 else { return LoanSchedule(principal: principal, rows: []) }

        let payment = terms.paymentOverride ?? annuityPayment(
            principal: principal, periodRate: rate, periods: terms.termPeriods
        )
        guard payment > 0 else { return LoanSchedule(principal: principal, rows: []) }

        var rows: [LoanScheduleRow] = []
        var balance = principal
        var index = 0

        while balance > 0, index < limit {
            index += 1
            guard let date = paymentDate(period: index, terms: terms, calendar: calendar) else { break }
            let interest = balance * rate
            let due = balance + interest

            var principalPart: Decimal
            var paymentAmount: Decimal
            if due <= payment || (hasFixedTerm && index == limit) {
                // Последний платёж забирает остаток целиком: иначе накопленная точность `Decimal`
                // оставила бы «хвост» в долях копейки и график не сходился бы в ноль.
                principalPart = balance
                paymentAmount = due
            } else {
                principalPart = payment - interest
                guard principalPart > 0 else {
                    // Платёж не покрывает проценты первого периода — долг не гасится вообще.
                    // Дальше он только растёт, поэтому график пустой, а не бесконечный.
                    return LoanSchedule(principal: principal, rows: [])
                }
                paymentAmount = payment
            }

            balance -= principalPart
            rows.append(LoanScheduleRow(
                index: index, date: date, payment: paymentAmount,
                interest: interest, principal: principalPart, balanceAfter: balance
            ))
        }

        return LoanSchedule(principal: principal, rows: rows)
    }

    // MARK: - Дифференцированный

    /// Тело гасится равными долями `P / n`, проценты начисляются на остаток → платёж убывает.
    /// `paymentOverride` здесь не применяется: у дифференцированного графика нет одного платежа,
    /// который можно было бы переопределить.
    private static func differentiatedSchedule(
        terms: LoanTerms,
        principal: Decimal,
        periodRate rate: Decimal,
        calendar: Calendar
    ) -> LoanSchedule {
        let periods = terms.termPeriods
        guard periods > 0 else { return LoanSchedule(principal: principal, rows: []) }

        let regularPrincipal = principal / Decimal(periods)
        var rows: [LoanScheduleRow] = []
        var balance = principal

        for index in 1...periods {
            guard let date = paymentDate(period: index, terms: terms, calendar: calendar) else { break }
            let interest = balance * rate
            let principalPart = index == periods ? balance : regularPrincipal
            balance -= principalPart
            rows.append(LoanScheduleRow(
                index: index, date: date, payment: principalPart + interest,
                interest: interest, principal: principalPart, balanceAfter: balance
            ))
        }

        return LoanSchedule(principal: principal, rows: rows)
    }

    // MARK: - Даты

    /// Даты периодов — через планировщик вклада: он уже умеет короткие месяцы (31-е → 30/28) и
    /// не сбивает якорь дня. Своей арифметики дат в кредите нет.
    static func paymentDate(
        period index: Int,
        terms: LoanTerms,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date? {
        guard index > 0 else { return nil }
        return DepositInterestScheduler.scheduledPeriodEnd(
            openingDate: terms.firstPaymentDate,
            months: (index - 1) * terms.frequency.stepMonths,
            payoutDay: calendar.component(.day, from: terms.firstPaymentDate),
            calendar: calendar
        )
    }
}
