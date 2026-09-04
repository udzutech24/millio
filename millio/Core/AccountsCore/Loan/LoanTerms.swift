import Foundation

/// Условия кредита — чистый вход расчётного ядра, без SwiftData.
///
/// Ядро не знает ни о `LoanContract`, ни о легаси `LoanMeta`: обе стороны приводятся к этой
/// структуре в `LoanTermsResolver`. Прогресс погашения (сколько платежей внесено, сколько
/// процентов уплачено) сюда НЕ входит — это факт по счёту, а не условие договора.
struct LoanTerms: Equatable, Sendable {
    var principal: Decimal
    /// Годовая ставка ЧИСЛОМ-ПРОЦЕНТОМ (18.9 = 18,9%), как `LoanMeta.rate`, — не доля.
    var annualRatePercent: Decimal
    /// Срок в ПЕРИОДАХ выбранной периодичности (60 при ежемесячной, 20 при квартальной).
    var termPeriods: Int
    var firstPaymentDate: Date
    var scheduleType: LoanScheduleType
    var frequency: LoanPaymentFrequency
    /// Платёж из договора банка либо новый платёж после досрочки-«срок».
    /// Задан → срок пересчитывается под него, `termPeriods` в расчёте не участвует (спека §4.2).
    var paymentOverride: Decimal?

    init(
        principal: Decimal,
        annualRatePercent: Decimal,
        termPeriods: Int,
        firstPaymentDate: Date,
        scheduleType: LoanScheduleType = .annuity,
        frequency: LoanPaymentFrequency = .monthly,
        paymentOverride: Decimal? = nil
    ) {
        self.principal = principal
        self.annualRatePercent = annualRatePercent
        self.termPeriods = termPeriods
        self.firstPaymentDate = firstPaymentDate
        self.scheduleType = scheduleType
        self.frequency = frequency
        self.paymentOverride = paymentOverride
    }
}

extension LoanTerms {
    /// Сид из легаси `LoanMeta` для счёта `.loan`, заведённого до появления договора (спека Р5).
    ///
    /// `LoanMeta` не хранит ни периодичности, ни даты первого платежа, ни срока в периодах —
    /// восстанавливаем: шаг всегда месячный, первый платёж = месяц от открытия счёта в
    /// `paymentDay`, срок = число месяцев до `termEnd`. Без `termEnd` срок неизвестен, и тогда
    /// единственный работающий вход — ручной платёж (график открытый). Нет ни того, ни другого —
    /// условий нет, возвращаем `nil` вместо выдуманных значений.
    init?(legacy meta: LoanMeta, openingDate: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        guard meta.principal > 0 else { return nil }
        guard let firstPayment = DepositInterestScheduler.scheduledPeriodEnd(
            openingDate: openingDate,
            months: 1,
            payoutDay: meta.paymentDay,
            calendar: calendar
        ) else { return nil }

        let periods: Int
        if let termEnd = meta.termEnd {
            let months = calendar.dateComponents([.month], from: firstPayment, to: termEnd).month ?? 0
            periods = max(months + 1, 1)
        } else if meta.monthlyPayment != nil {
            periods = 0
        } else {
            return nil
        }

        self.init(
            principal: meta.principal,
            annualRatePercent: meta.rate,
            termPeriods: periods,
            firstPaymentDate: firstPayment,
            scheduleType: meta.scheduleType,
            frequency: .monthly,
            paymentOverride: meta.monthlyPayment
        )
    }
}
