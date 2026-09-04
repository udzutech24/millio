import Foundation

/// Витрина деталки кредита (макет, ЭКРАН 1): все цифры экрана считает `LoanScheduleEngine`,
/// вью не считает ничего и второго определения остатка не заводит.
///
/// Разделение источников намеренное и описано в спеке:
/// - **деньги** — из ленты `AccountEvent` (`outstandingPrincipal`, Р6): именно она уменьшается
///   платежом и именно она даёт вклад счёта в net worth;
/// - **позиция в графике и даты** — из договора (`paymentsMade`): в ленте нет понятия «период».
struct LoanDetailPresentation: Equatable {
    let currency: String
    /// Исходная сумма кредита — база прогресс-бара «погашено N из P».
    let principal: Decimal
    /// Остаток тела долга сейчас.
    let outstandingPrincipal: Decimal
    let paidPrincipal: Decimal
    /// Доля погашенного тела, 0...1.
    let progress: Decimal
    let payoffDate: Date?
    let nextPayment: Decimal?
    let nextPaymentDate: Date?
    let nextPaymentPrincipal: Decimal?
    let nextPaymentInterest: Decimal?
    let paidInterestTotal: Decimal
    let paymentsMade: Int
    /// Сколько платежей осталось по фактическому остатку, а не по исходному сроку.
    let paymentsAhead: Int
    let termPeriods: Int
    let termMonths: Int
    let annualRatePercent: Decimal
    let scheduleType: LoanScheduleType
    let frequency: LoanPaymentFrequency

    static func make(
        terms: LoanTerms,
        outstandingPrincipal: Decimal,
        paymentsMade: Int,
        paidInterestTotal: Decimal,
        currency: String,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> LoanDetailPresentation {
        let principal = max(terms.principal, .zero)
        let outstanding = max(outstandingPrincipal, .zero)
        let ahead = LoanScheduleEngine.schedule(
            terms: remainingTerms(terms: terms, outstanding: outstanding, paymentsMade: paymentsMade, calendar: calendar),
            calendar: calendar
        )
        let nextRow = ahead.rows.first

        return LoanDetailPresentation(
            currency: currency,
            principal: principal,
            outstandingPrincipal: outstanding,
            paidPrincipal: max(principal - outstanding, .zero),
            progress: principal > 0 ? min(max((principal - outstanding) / principal, .zero), 1) : .zero,
            payoffDate: ahead.payoffDate,
            nextPayment: nextRow?.payment,
            nextPaymentDate: nextRow?.date,
            nextPaymentPrincipal: nextRow?.principal,
            nextPaymentInterest: nextRow?.interest,
            paidInterestTotal: paidInterestTotal,
            paymentsMade: paymentsMade,
            paymentsAhead: ahead.paymentCount,
            termPeriods: terms.termPeriods,
            termMonths: terms.termPeriods * terms.frequency.stepMonths,
            annualRatePercent: terms.annualRatePercent,
            scheduleType: terms.scheduleType,
            frequency: terms.frequency
        )
    }

    /// График «впереди» строится от ФАКТИЧЕСКОГО остатка (Р6), а не обрезается с конца исходного:
    /// после досрочного погашения (Ф6) остаток уже не совпадает с расчётной точкой графика, и
    /// обрезка показывала бы платёж и дату закрытия из несуществующего сценария.
    ///
    /// Платёж при этом не «плывёт»: аннуитет самоподобен — `annuity(остаток, i, оставшихся периодов)`
    /// равен исходному платежу. Ручной платёж договора (`paymentOverride`) переносится как есть,
    /// он же и определяет число оставшихся периодов.
    private static func remainingTerms(
        terms: LoanTerms,
        outstanding: Decimal,
        paymentsMade: Int,
        calendar: Calendar
    ) -> LoanTerms {
        var remaining = terms
        remaining.principal = outstanding
        remaining.termPeriods = max(terms.termPeriods - max(paymentsMade, 0), 0)
        if let nextDate = LoanScheduleEngine.paymentDate(
            period: max(paymentsMade, 0) + 1, terms: terms, calendar: calendar
        ) {
            remaining.firstPaymentDate = nextDate
        }
        return remaining
    }
}

// MARK: - Форматирование

extension LoanDetailPresentation {
    /// Один символ валюты на всех экранах кредита — тот же резолвер, что у hero счетов.
    var currencySymbol: String {
        MonetaCurrency(rawValue: currency)?.symbol ?? currency
    }

    /// Деньги кредита — целые рубли, как в hero и в строке списка счетов. Единственная точка
    /// округления на экране: ядро считает без округлений (контракт §4.3).
    func money(_ value: Decimal) -> String {
        let text = AccountRowAmountFormatter.text(
            NSDecimalNumber(decimal: value).doubleValue,
            isHidden: false,
            maximumFractionDigits: 0
        )
        return "\(text) \(currencySymbol)"
    }

    /// Прогресс с одним знаком после запятой — «5,2%» макета.
    var progressText: String {
        let percent = NSDecimalNumber(decimal: progress * 100).doubleValue
        let number = percent.formatted(
            .number.locale(AppLocalization.currentAppLocale).precision(.fractionLength(1))
        )
        return "\(number)%"
    }
}
