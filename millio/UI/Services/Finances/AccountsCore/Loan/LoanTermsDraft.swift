import Foundation

/// Редактируемое состояние формы «Условия кредита» — один черновик на оба режима (создание и правка).
///
/// Отдельный тип, а не россыпь `@State` во вью: собирать `LoanTerms` из текстовых полей нужно
/// одинаково в обоих режимах, и это единственная часть экрана, которую имеет смысл покрыть тестом.
///
/// Срок здесь в МЕСЯЦАХ — так его называет договор и так его вводит человек («кредит на 60 месяцев»),
/// тогда как ядро считает в периодах выбранной периодичности. Пересчёт живёт здесь, чтобы форма
/// не знала про `stepMonths`, а ядро — про месяцы.
struct LoanTermsDraft: Equatable {
    /// Канонический raw `AmountTextField` (разделитель "."), не отображаемая строка с разрядами.
    var principalText: String = ""
    var ratePercentText: String = ""
    var termMonths: Int = 12
    var firstPaymentDate: Date = Date()
    var scheduleType: LoanScheduleType = .annuity
    var frequency: LoanPaymentFrequency = .monthly
    /// Тумблер «Задать платёж вручную»: выключен — платёж считает ядро, включён — берём из договора.
    var isManualPayment: Bool = false
    var paymentText: String = ""

    /// Потолок срока: 40 лет перекрывает ипотеку и не даёт пикеру превратиться в бесконечный список.
    static let maxTermMonths = 480

    init(firstPaymentDate: Date = Date()) {
        self.firstPaymentDate = firstPaymentDate
    }

    /// Сид из уже существующих условий (договор V12 либо легаси-мета через `LoanTermsResolver`).
    init(terms: LoanTerms) {
        principalText = Self.rawText(terms.principal)
        ratePercentText = Self.rawText(terms.annualRatePercent)
        termMonths = max(terms.termPeriods, 0) * terms.frequency.stepMonths
        firstPaymentDate = terms.firstPaymentDate
        scheduleType = terms.scheduleType
        frequency = terms.frequency
        isManualPayment = terms.paymentOverride != nil
        paymentText = terms.paymentOverride.map(Self.rawText) ?? ""
    }
}

// MARK: - Разбор полей

extension LoanTermsDraft {
    var principal: Decimal? { Self.decimal(from: principalText) }
    var ratePercent: Decimal? { Self.decimal(from: ratePercentText) }
    var manualPayment: Decimal? { isManualPayment ? Self.decimal(from: paymentText) : nil }

    /// Срок в периодах ядра. Месяцы всегда кратны шагу (`alignTermToFrequency`), поэтому деление точное.
    var termPeriods: Int { max(termMonths / frequency.stepMonths, 0) }

    /// Условия для ядра либо `nil`, если форму ещё нельзя сохранить.
    ///
    /// Срок = 0 допустим только при ручном платеже: тогда график открытый и число строк определяет
    /// сам платёж (спека §4.2). Без ручного платежа нулевой срок не даёт ни платежа, ни графика.
    var terms: LoanTerms? {
        guard let principal, principal > 0 else { return nil }
        guard let ratePercent, ratePercent >= 0 else { return nil }
        let payment = manualPayment
        if isManualPayment {
            guard let payment, payment > 0 else { return nil }
        } else {
            guard termPeriods > 0 else { return nil }
        }
        return LoanTerms(
            principal: principal,
            annualRatePercent: ratePercent,
            termPeriods: termPeriods,
            firstPaymentDate: firstPaymentDate,
            scheduleType: scheduleType,
            frequency: frequency,
            paymentOverride: payment
        )
    }

    /// Платёж «по формуле» — то, что ядро посчитало бы БЕЗ ручного значения. Именно эту сумму
    /// показывает подсказка под тумблером, поэтому `paymentOverride` здесь принудительно снят:
    /// иначе подсказка повторяла бы то, что человек только что вписал.
    var calculatedPayment: Decimal? {
        guard var base = terms else { return nil }
        base.paymentOverride = nil
        guard base.termPeriods > 0 else { return nil }
        guard let payment = LoanScheduleEngine.regularPayment(terms: base), payment > 0 else { return nil }
        return DepositInterestScheduler.round2(payment)
    }

    /// Варианты срока для пикера — только кратные шагу периодичности: при квартальных платежах
    /// «61 месяц» не существует, такой срок не разложится в целое число периодов.
    var termMonthOptions: [Int] {
        let step = frequency.stepMonths
        return stride(from: step, through: Self.maxTermMonths, by: step).map { $0 }
    }

    /// Подтягивает срок к ближайшему кратному шагу вверх — вызывается при смене периодичности.
    mutating func alignTermToFrequency() {
        let step = frequency.stepMonths
        guard step > 1, termMonths % step != 0 else { return }
        termMonths = min(((termMonths / step) + 1) * step, Self.maxTermMonths)
    }

    // MARK: - Числа ↔ текст

    /// `Decimal` → канонический raw для `AmountTextField` (разделитель ".", без разрядов).
    private static func rawText(_ value: Decimal) -> String {
        AmountTextField.canonical(from: NSDecimalNumber(decimal: value).stringValue)
    }

    private static func decimal(from text: String) -> Decimal? {
        let sanitized = AmountInputFormatter.sanitize(text)
        guard !sanitized.isEmpty else { return nil }
        return Decimal(string: sanitized)
    }
}
