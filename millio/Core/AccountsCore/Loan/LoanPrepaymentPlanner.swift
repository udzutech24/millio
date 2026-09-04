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
    /// Регулярный платёж после досрочки.
    let payment: Decimal
    let remainingPayments: Int
    /// Разница с числом платежей без досрочки. Отрицательная = срок сократился.
    let paymentsDelta: Int
    let payoffDate: Date?
    let interestAhead: Decimal
    /// Экономия на процентах против графика без досрочки. Отрицательная при недоплате.
    let savings: Decimal
}

/// Оба сценария от одного и того же нового остатка + база для сравнения.
struct LoanPrepaymentPlan: Equatable, Sendable {
    let balanceBefore: Decimal
    let balanceAfter: Decimal
    let baselinePayment: Decimal
    let baselineRemainingPayments: Int
    let baselinePayoffDate: Date?
    let baselineInterestAhead: Decimal
    let term: LoanPrepaymentPreview
    let payment: LoanPrepaymentPreview
}

/// Досрочное погашение: «сократить срок» или «сократить платёж» от одного нового остатка.
///
/// Экономия считается разницей процентов впереди по ДВУМ фактическим графикам, а не по закрытой
/// формуле: на эталонном сценарии формула даёт 226 817 ₽, график — 226 771 ₽, и владелец выбрал
/// график (спека §4.4).
enum LoanPrepaymentPlanner {

    /// `amount` может быть и меньше планового платежа (недоплата) — тогда остаток уменьшается
    /// слабее, срок растёт, `savings` уходит в минус. Это валидный сценарий того же листа.
    ///
    /// Возвращает `nil`, когда сценарий бессмысленен: график не строится, все платежи уже внесены
    /// или график дифференцированный (у него нет единого платежа, «сократить платёж» не определено —
    /// продуктом это пока не поддерживается, спека §10).
    static func plan(
        terms: LoanTerms,
        paymentsMade: Int,
        amount: Decimal,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> LoanPrepaymentPlan? {
        guard terms.scheduleType == .annuity else { return nil }
        guard amount > 0 else { return nil }

        let baseline = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
        let made = max(0, paymentsMade)
        guard baseline.amortizes, made < baseline.paymentCount else { return nil }
        guard let regularPayment = LoanScheduleEngine.regularPayment(terms: terms), regularPayment > 0 else { return nil }
        guard let nextDate = baseline.nextPaymentDate(afterPayments: made) else { return nil }

        let balanceBefore = baseline.outstandingPrincipal(afterPayments: made)
        let remaining = baseline.paymentCount - made
        let interestAheadBefore = baseline.interestAhead(afterPayments: made)
        let balanceAfter = max(balanceBefore - amount, .zero)

        var continuation = terms
        continuation.principal = balanceAfter
        continuation.firstPaymentDate = nextDate

        // Полное досрочное погашение: обоим сценариям платить больше нечего.
        guard balanceAfter > 0 else {
            let closed = LoanPrepaymentPreview(
                strategy: .term, payment: .zero, remainingPayments: 0, paymentsDelta: -remaining,
                payoffDate: nil, interestAhead: .zero, savings: interestAheadBefore
            )
            return LoanPrepaymentPlan(
                balanceBefore: balanceBefore, balanceAfter: .zero,
                baselinePayment: regularPayment, baselineRemainingPayments: remaining,
                baselinePayoffDate: baseline.payoffDate, baselineInterestAhead: interestAheadBefore,
                term: closed,
                payment: LoanPrepaymentPreview(
                    strategy: .payment, payment: .zero, remainingPayments: 0, paymentsDelta: -remaining,
                    payoffDate: nil, interestAhead: .zero, savings: interestAheadBefore
                )
            )
        }

        // «Срок»: платёж прежний, число строк — сколько получится до обнуления остатка.
        var termTerms = continuation
        termTerms.paymentOverride = regularPayment
        let termSchedule = LoanScheduleEngine.schedule(terms: termTerms, calendar: calendar)

        // «Платёж»: число платежей прежнее, платёж пересчитывается под новый остаток.
        var paymentTerms = continuation
        paymentTerms.termPeriods = remaining
        paymentTerms.paymentOverride = nil
        let paymentSchedule = LoanScheduleEngine.schedule(terms: paymentTerms, calendar: calendar)

        return LoanPrepaymentPlan(
            balanceBefore: balanceBefore,
            balanceAfter: balanceAfter,
            baselinePayment: regularPayment,
            baselineRemainingPayments: remaining,
            baselinePayoffDate: baseline.payoffDate,
            baselineInterestAhead: interestAheadBefore,
            term: preview(
                strategy: .term,
                payment: regularPayment,
                schedule: termSchedule,
                baselineRemaining: remaining,
                baselineInterestAhead: interestAheadBefore
            ),
            payment: preview(
                strategy: .payment,
                payment: LoanScheduleEngine.annuityPayment(
                    principal: balanceAfter,
                    periodRate: LoanScheduleEngine.periodRate(
                        annualRatePercent: terms.annualRatePercent, frequency: terms.frequency
                    ),
                    periods: remaining
                ),
                schedule: paymentSchedule,
                baselineRemaining: remaining,
                baselineInterestAhead: interestAheadBefore
            )
        )
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
