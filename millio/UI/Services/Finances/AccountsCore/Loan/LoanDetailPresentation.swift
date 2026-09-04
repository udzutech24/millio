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
        // «Что впереди» считает ядро (`LoanScheduleEngine.remainingTerms`), а не экран: тем же
        // методом живут график (Ф5) и лист досрочного погашения (Ф6), поэтому «N впереди» на
        // деталке и число строк на других экранах — одно число по построению, а не по совпадению.
        let ahead = LoanScheduleEngine.schedule(
            terms: LoanScheduleEngine.remainingTerms(
                terms: terms, outstanding: outstanding, paymentsMade: paymentsMade, calendar: calendar
            ),
            calendar: calendar
        )
        let nextRow = ahead.rows.first
        // Открытый график (срок задаёт платёж, §4.2 — так приезжают счета из старого мира): срока
        // в договоре нет, и «0 мес» на чипсе было бы ложью. Показываем то, что реально впереди.
        let termPeriods = terms.termPeriods > 0 ? terms.termPeriods : ahead.paymentCount

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
            termPeriods: termPeriods,
            termMonths: termPeriods * terms.frequency.stepMonths,
            annualRatePercent: terms.annualRatePercent,
            scheduleType: terms.scheduleType,
            frequency: terms.frequency
        )
    }

}

// MARK: - Форматирование

extension LoanDetailPresentation {
    /// Один символ валюты на всех экранах кредита — тот же резолвер, что у hero счетов.
    var currencySymbol: String { LoanMoneyFormat.symbol(for: currency) }

    /// Деньги кредита — целые рубли, как в hero и в строке списка счетов. Единственная точка
    /// округления на экране: ядро считает без округлений (контракт §4.3).
    func money(_ value: Decimal) -> String { LoanMoneyFormat.money(value, currency: currency) }

    /// Прогресс с одним знаком после запятой — «5,2%» макета.
    var progressText: String { LoanMoneyFormat.percent(progress) }
}
