import Foundation

/// Что сокращаем досрочным платежом.
enum LoanPrepaymentStrategy: String, CaseIterable, Sendable {
    /// Платёж прежний, срок уменьшается. Предвыбран в UI (решение владельца).
    case term
    /// Срок прежний, платёж уменьшается.
    case payment
}

/// Один сценарий досрочного погашения — то, что показывает лист «было → стало».
struct LoanPrepaymentPreview: Equatable, Sendable {
    let strategy: LoanPrepaymentStrategy
    /// Регулярный платёж после досрочки. У дифференцированного графика — ближайший платёж:
    /// единственный, который в нём определён (дальше он убывает сам).
    let payment: Decimal
    let remainingPayments: Int
    /// Разница с числом платежей без досрочки. Отрицательная = срок сократился.
    let paymentsDelta: Int
    let payoffDate: Date?
    let interestAhead: Decimal
    /// Экономия на процентах против графика без досрочки.
    let savings: Decimal
}

/// Оба сценария от одного и того же нового остатка + база для сравнения.
struct LoanPrepaymentPlan: Equatable, Sendable {
    let balanceBefore: Decimal
    let balanceAfter: Decimal
    /// Сколько реально спишется: внести больше остатка нельзя, иначе долг ушёл бы в плюс
    /// и счёт-обязательство стал бы активом в net worth.
    let appliedAmount: Decimal
    /// Ближайший плановый платёж — им же отделяется недоплата от досрочки.
    let baselinePayment: Decimal
    let baselineRemainingPayments: Int
    let baselinePayoffDate: Date?
    let baselineInterestAhead: Decimal
    /// Дата ближайшего планового платежа: досрочка её не двигает («останется прежним»).
    let nextPaymentDate: Date
    let term: LoanPrepaymentPreview
    /// `nil`, когда сценарий «сократить платёж» не определён: у дифференцированного графика
    /// платёж убывает сам (спека §10), а при полном погашении платить больше нечего.
    let payment: LoanPrepaymentPreview?

    /// Внесённой суммы хватает, чтобы закрыть кредит целиком.
    var closesLoan: Bool { balanceAfter == .zero }

    func preview(for strategy: LoanPrepaymentStrategy) -> LoanPrepaymentPreview? {
        switch strategy {
        case .term: term
        case .payment: payment
        }
    }
}

/// Недоплата: внесено МЕНЬШЕ ближайшего планового платежа (решение владельца — тот же лист).
///
/// Проценты периода закрываются первыми, до тела доходит остаток суммы; если не хватило даже на
/// проценты, тело не уменьшается вовсе. Период при этом расходуется — именно поэтому срок растёт.
struct LoanUnderpaymentPlan: Equatable, Sendable {
    let balanceBefore: Decimal
    let balanceAfter: Decimal
    /// Плановый платёж, с которым сравнивали, — он же остаётся платежом дальше.
    let scheduledPayment: Decimal
    /// Проценты периода целиком — их и не хватает закрыть, когда `principalPart` нулевой.
    let periodInterest: Decimal
    let interestPart: Decimal
    let principalPart: Decimal
    let baselineRemainingPayments: Int
    let baselinePayoffDate: Date?
    let baselineInterestAhead: Decimal
    /// Платежей впереди ПОСЛЕ этой недоплаты (саму недоплату сюда не считаем — она уже внесена).
    let remainingPayments: Int
    /// На сколько платежей вырос срок. Положительная величина — недоплата срок не сокращает.
    let paymentsDelta: Int
    let payoffDate: Date?
    let interestAhead: Decimal
    /// На сколько вырастет переплата за оставшуюся жизнь кредита: проценты, уплаченные сейчас,
    /// плюс проценты впереди — против того, что было бы при платеже по графику.
    let extraInterest: Decimal
    /// Платёж, который надо закрепить в договоре, чтобы дальше он не «поплыл» (аннуитет).
    let pinnedPayment: Decimal?
}

/// Что записать в ленту счёта и в договор при подтверждении листа.
///
/// Решение принимает ядро, а не экран: досрочка уходит в тело целиком и период не расходует,
/// недоплата сначала закрывает проценты периода и период расходует.
struct LoanExtraPaymentEntry: Equatable, Sendable {
    let principalPart: Decimal
    let interestPart: Decimal
    /// Недоплата занимает период графика, досрочка — нет («ближайший платёж останется прежним»).
    let consumesPeriod: Bool
    /// Платёж, закрепляемый в `LoanContract.paymentOverride` (спека Р8: журнал досрочек не храним,
    /// график всегда строится от фактического остатка, поэтому платёж — единственное, что нужно
    /// запомнить). `nil` — договор не трогаем.
    let pinnedPayment: Decimal?
}

/// Во что превращается внесённая сумма: досрочное погашение или недоплата.
enum LoanExtraPayment: Equatable, Sendable {
    case prepayment(LoanPrepaymentPlan)
    case underpayment(LoanUnderpaymentPlan)
}

/// Планировщик внеплановой суммы по кредиту: досрочное погашение («срок» или «платёж») и недоплата.
///
/// Экономия считается разницей процентов впереди по ДВУМ фактическим графикам, а не по закрытой
/// формуле: на эталонном сценарии формула даёт 226 817 ₽, график — 226 771 ₽, и владелец выбрал
/// график (спека §4.4).
enum LoanPrepaymentPlanner {

    /// Единственная точка входа для листа: ядро само решает, досрочка это или недоплата.
    ///
    /// Граница — ближайший ПЛАНОВЫЙ платёж: всё, что меньше него, человек вносит вместо платежа,
    /// а не сверх него, и тогда проценты периода закрываются первыми. Всё, что больше или равно, —
    /// сумма сверх графика, она уходит в тело целиком («ближайший платёж останется прежним»).
    static func evaluate(
        terms: LoanTerms,
        outstandingPrincipal: Decimal,
        paymentsMade: Int,
        amount: Decimal,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> LoanExtraPayment? {
        guard amount > 0,
              let baseline = baseline(
                  terms: terms, outstandingPrincipal: outstandingPrincipal,
                  paymentsMade: paymentsMade, calendar: calendar
              )
        else { return nil }

        return amount < baseline.payment
            ? .underpayment(underpayment(baseline: baseline, amount: amount, calendar: calendar))
            : .prepayment(plan(baseline: baseline, amount: amount, calendar: calendar))
    }

    /// Досрочное погашение: сумма СВЕРХ графика уходит в тело целиком.
    ///
    /// Возвращает `nil`, когда сценария нет вовсе: график не строится, все платежи уже внесены
    /// или сумма неположительная.
    static func plan(
        terms: LoanTerms,
        outstandingPrincipal: Decimal,
        paymentsMade: Int,
        amount: Decimal,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> LoanPrepaymentPlan? {
        guard amount > 0,
              let baseline = baseline(
                  terms: terms, outstandingPrincipal: outstandingPrincipal,
                  paymentsMade: paymentsMade, calendar: calendar
              )
        else { return nil }
        return plan(baseline: baseline, amount: amount, calendar: calendar)
    }

    /// Недоплата: сумма МЕНЬШЕ планового платежа. Отдельный вход нужен тестам и `evaluate`.
    static func underpayment(
        terms: LoanTerms,
        outstandingPrincipal: Decimal,
        paymentsMade: Int,
        amount: Decimal,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> LoanUnderpaymentPlan? {
        guard amount > 0,
              let baseline = baseline(
                  terms: terms, outstandingPrincipal: outstandingPrincipal,
                  paymentsMade: paymentsMade, calendar: calendar
              )
        else { return nil }
        return underpayment(baseline: baseline, amount: amount, calendar: calendar)
    }

    /// Ближайший ПЛАНОВЫЙ платёж «от сегодня»: подсказка листа и граница «недоплата / досрочка».
    static func scheduledPayment(
        terms: LoanTerms,
        outstandingPrincipal: Decimal,
        paymentsMade: Int,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> (amount: Decimal, date: Date)? {
        guard let baseline = baseline(
            terms: terms, outstandingPrincipal: outstandingPrincipal,
            paymentsMade: paymentsMade, calendar: calendar
        ) else { return nil }
        return (baseline.payment, baseline.nextDate)
    }

    // MARK: - База сравнения

    /// График «от сегодня»: то же, что показывают деталка и экран графика. Всё сравнение листа
    /// идёт против него, поэтому «было» в листе дословно совпадает с цифрами деталки.
    private struct Baseline {
        let terms: LoanTerms
        /// Условия «от сегодня» — вход всех продолжений графика.
        let remaining: LoanTerms
        let schedule: LoanSchedule
        let balance: Decimal
        let nextDate: Date
        /// Ближайший плановый платёж.
        let payment: Decimal
        /// Тело в ближайшем платеже — «скорость» дифференцированного графика.
        let principalPerPeriod: Decimal
        let interest: Decimal
    }

    private static func baseline(
        terms: LoanTerms,
        outstandingPrincipal: Decimal,
        paymentsMade: Int,
        calendar: Calendar
    ) -> Baseline? {
        let balance = max(outstandingPrincipal, .zero)
        guard balance > 0 else { return nil }
        let remaining = LoanScheduleEngine.remainingTerms(
            terms: terms, outstanding: balance, paymentsMade: paymentsMade, calendar: calendar
        )
        let schedule = LoanScheduleEngine.schedule(terms: remaining, calendar: calendar)
        guard let first = schedule.rows.first else { return nil }
        return Baseline(
            terms: terms,
            remaining: remaining,
            schedule: schedule,
            balance: balance,
            nextDate: first.date,
            payment: first.payment,
            principalPerPeriod: first.principal,
            interest: first.interest
        )
    }

    // MARK: - Досрочное погашение

    private static func plan(baseline: Baseline, amount: Decimal, calendar: Calendar) -> LoanPrepaymentPlan {
        let applied = min(amount, baseline.balance)
        let balanceAfter = baseline.balance - applied
        let baselineRemaining = baseline.schedule.paymentCount
        let baselineInterestAhead = baseline.schedule.totalOverpayment

        func makePlan(term: LoanPrepaymentPreview, payment: LoanPrepaymentPreview?) -> LoanPrepaymentPlan {
            LoanPrepaymentPlan(
                balanceBefore: baseline.balance,
                balanceAfter: balanceAfter,
                appliedAmount: applied,
                baselinePayment: baseline.payment,
                baselineRemainingPayments: baselineRemaining,
                baselinePayoffDate: baseline.schedule.payoffDate,
                baselineInterestAhead: baselineInterestAhead,
                nextPaymentDate: baseline.nextDate,
                term: term,
                payment: payment
            )
        }

        // Полное досрочное погашение: выбирать нечего, дальше платежей нет.
        guard balanceAfter > 0 else {
            return makePlan(
                term: LoanPrepaymentPreview(
                    strategy: .term, payment: .zero, remainingPayments: 0,
                    paymentsDelta: -baselineRemaining, payoffDate: nil,
                    interestAhead: .zero, savings: baselineInterestAhead
                ),
                payment: nil
            )
        }

        // «Срок»: скорость погашения прежняя (платёж у аннуитета, тело в периоде у
        // дифференцированного), число периодов пересчитывается под новый остаток.
        let termSchedule = LoanScheduleEngine.schedule(
            terms: continuationKeepingPace(
                baseline: baseline, balance: balanceAfter, firstDate: baseline.nextDate
            ),
            calendar: calendar
        )
        let term = preview(
            strategy: .term,
            payment: termSchedule.rows.first?.payment ?? baseline.payment,
            schedule: termSchedule,
            baselineRemaining: baselineRemaining,
            baselineInterestAhead: baselineInterestAhead
        )

        // «Платёж»: число платежей прежнее, платёж пересчитывается под новый остаток. У
        // дифференцированного графика такого сценария нет — платёж в нём убывает сам (спека §10).
        guard baseline.terms.scheduleType == .annuity else {
            return makePlan(term: term, payment: nil)
        }
        var paymentTerms = baseline.remaining
        paymentTerms.principal = balanceAfter
        paymentTerms.termPeriods = baselineRemaining
        paymentTerms.paymentOverride = nil
        let paymentSchedule = LoanScheduleEngine.schedule(terms: paymentTerms, calendar: calendar)

        return makePlan(
            term: term,
            payment: preview(
                strategy: .payment,
                payment: paymentSchedule.rows.first?.payment ?? .zero,
                schedule: paymentSchedule,
                baselineRemaining: baselineRemaining,
                baselineInterestAhead: baselineInterestAhead
            )
        )
    }

    // MARK: - Недоплата

    private static func underpayment(
        baseline: Baseline, amount: Decimal, calendar: Calendar
    ) -> LoanUnderpaymentPlan {
        let interestPart = min(amount, baseline.interest)
        // Суммы не хватило даже на проценты периода — тело не уменьшается. Штрафов и капитализации
        // недоплаченных процентов модель не знает (спека §10), поэтому долг просто стоит на месте.
        let principalPart = max(amount - baseline.interest, .zero)
        let balanceAfter = max(baseline.balance - principalPart, .zero)
        let baselineRemaining = baseline.schedule.paymentCount
        let baselineInterestAhead = baseline.schedule.totalOverpayment

        // Период израсходован: следующий платёж — через один шаг от ближайшего.
        let nextDate = LoanScheduleEngine.paymentDate(period: 2, terms: baseline.remaining, calendar: calendar)
            ?? baseline.nextDate
        let after = LoanScheduleEngine.schedule(
            terms: continuationKeepingPace(baseline: baseline, balance: balanceAfter, firstDate: nextDate),
            calendar: calendar
        )

        return LoanUnderpaymentPlan(
            balanceBefore: baseline.balance,
            balanceAfter: balanceAfter,
            scheduledPayment: baseline.payment,
            periodInterest: baseline.interest,
            interestPart: interestPart,
            principalPart: principalPart,
            baselineRemainingPayments: baselineRemaining,
            baselinePayoffDate: baseline.schedule.payoffDate,
            baselineInterestAhead: baselineInterestAhead,
            remainingPayments: after.paymentCount,
            // Недоплата тоже занимает период — поэтому в сравнение со сроком «по графику» она
            // входит единицей: 1 внесённый платёж + то, что осталось после него.
            paymentsDelta: (after.paymentCount + 1) - baselineRemaining,
            payoffDate: after.payoffDate,
            interestAhead: after.totalOverpayment,
            extraInterest: (interestPart + after.totalOverpayment) - baselineInterestAhead,
            pinnedPayment: baseline.terms.scheduleType == .annuity ? baseline.payment : nil
        )
    }

    // MARK: - Общее

    /// Продолжение графика от нового остатка при НЕИЗМЕННОЙ скорости погашения: у аннуитета это
    /// прежний платёж, у дифференцированного — прежнее тело в периоде. Так ведёт себя банк и при
    /// досрочке «сократить срок», и при недоплате: пересчитывается число периодов, а не платёж.
    private static func continuationKeepingPace(
        baseline: Baseline, balance: Decimal, firstDate: Date
    ) -> LoanTerms {
        var continuation = baseline.remaining
        continuation.principal = balance
        continuation.firstPaymentDate = firstDate
        switch baseline.terms.scheduleType {
        case .annuity:
            continuation.paymentOverride = baseline.payment
        case .differentiated:
            continuation.paymentOverride = nil
            continuation.termPeriods = LoanScheduleEngine.periodsKeepingPrincipalPace(
                balance: balance, principalPerPeriod: baseline.principalPerPeriod
            )
        }
        return continuation
    }

    private static func preview(
        strategy: LoanPrepaymentStrategy,
        payment: Decimal,
        schedule: LoanSchedule,
        baselineRemaining: Int,
        baselineInterestAhead: Decimal
    ) -> LoanPrepaymentPreview {
        LoanPrepaymentPreview(
            strategy: strategy,
            payment: payment,
            remainingPayments: schedule.paymentCount,
            paymentsDelta: schedule.paymentCount - baselineRemaining,
            payoffDate: schedule.payoffDate,
            interestAhead: schedule.totalOverpayment,
            savings: baselineInterestAhead - schedule.totalOverpayment
        )
    }
}

// MARK: - Что записывать при подтверждении

extension LoanPrepaymentPlan {
    /// Досрочка уходит в тело целиком, период не расходует.
    ///
    /// Выбранный платёж закрепляется в договоре обязательно — и в сценарии «платёж», и в сценарии
    /// «срок»: аннуитет самоподобен, и без закрепления следующий пересчёт графика от нового остатка
    /// вернул бы прежнее число платежей с уменьшенным платежом, то есть молча подменил бы «срок»
    /// на «платёж». У дифференцированного графика закреплять нечего — там постоянно тело в периоде,
    /// и число периодов пересчитывается от остатка (`LoanScheduleEngine.remainingTerms`).
    func entry(for strategy: LoanPrepaymentStrategy) -> LoanExtraPaymentEntry? {
        guard let preview = preview(for: strategy) else { return nil }
        let pinned = !closesLoan && preview.payment > 0 && payment != nil ? preview.payment : nil
        return LoanExtraPaymentEntry(
            principalPart: appliedAmount,
            interestPart: .zero,
            consumesPeriod: false,
            pinnedPayment: pinned
        )
    }
}

extension LoanUnderpaymentPlan {
    var entry: LoanExtraPaymentEntry {
        LoanExtraPaymentEntry(
            principalPart: principalPart,
            interestPart: interestPart,
            consumesPeriod: true,
            pinnedPayment: pinnedPayment
        )
    }
}
