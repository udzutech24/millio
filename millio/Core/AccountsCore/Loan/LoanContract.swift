import Foundation
import SwiftData

/// Договор по кредиту: условия и прогресс погашения счёта `.loan` в детальном режиме.
///
/// Отдельная таблица, а не поля в `Account.loanMeta`: `LoanMeta` — composite attribute внутри
/// `Account`, и любое новое поле в нём сдвигает checksum `Account` задним числом во всех версиях
/// схемы V7–V11 → `NSCocoaErrorDomain 134504` на сторах, которые уже существуют
/// (памятка `millio-schema-frozen-types-trap`, тот же довод, что у `AccountAppearance`).
///
/// Связь с `Account` — по `accountID` без `@Relationship`: реляция включила бы `LoanContract`
/// в граф `Account` и снова сдвинула бы его checksum. Доступ — только через `LoanContractStore`.
///
/// Фактический остаток долга здесь НЕ хранится: он живёт в ленте `AccountEvent` (спека Р6),
/// а `paymentsMade`/`paidInterestTotal` — накопители прогресса для карточки и графика.
@Model
final class LoanContract: Persistable {
    // Без @Attribute(.unique): CloudKit-конфигурация не поддерживает unique-констрейнты
    // (тот же контракт, что у всех моделей проекта).
    var id: UUID = UUID()
    var accountID: UUID = UUID()
    /// Исходная сумма кредита — база прогресс-бара «погашено N из P».
    var principal: Decimal = Decimal.zero
    /// Годовая ставка числом-процентом (18.9 = 18,9%).
    var annualRatePercent: Decimal = Decimal.zero
    /// Срок в периодах выбранной периодичности, а не в месяцах.
    var termPeriods: Int = 0
    var firstPaymentDate: Date = Date()
    var scheduleTypeRaw: String = LoanScheduleType.annuity.rawValue
    var frequencyRaw: String = LoanPaymentFrequency.monthly.rawValue
    /// Платёж из договора банка либо новый платёж после досрочки-«платёж».
    var paymentOverride: Decimal?
    var paymentsMade: Int = 0
    /// Накопитель уплаченных процентов: растёт с каждым платежом, графиком не пересчитывается —
    /// иначе досрочки и пропуски переписывали бы прошлое.
    var paidInterestTotal: Decimal = Decimal.zero
    /// Страховка — отдельная строка расхода, в платёж не входит (UI отложен, спека §10).
    var insuranceAmount: Decimal?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        accountID: UUID,
        principal: Decimal = .zero,
        annualRatePercent: Decimal = .zero,
        termPeriods: Int = 0,
        firstPaymentDate: Date = Date(),
        scheduleType: LoanScheduleType = .annuity,
        frequency: LoanPaymentFrequency = .monthly,
        paymentOverride: Decimal? = nil,
        paymentsMade: Int = 0,
        paidInterestTotal: Decimal = .zero,
        insuranceAmount: Decimal? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountID = accountID
        self.principal = principal
        self.annualRatePercent = annualRatePercent
        self.termPeriods = termPeriods
        self.firstPaymentDate = firstPaymentDate
        self.scheduleTypeRaw = scheduleType.rawValue
        self.frequencyRaw = frequency.rawValue
        self.paymentOverride = paymentOverride
        self.paymentsMade = paymentsMade
        self.paidInterestTotal = paidInterestTotal
        self.insuranceAmount = insuranceAmount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var scheduleType: LoanScheduleType {
        get { LoanScheduleType(rawValue: scheduleTypeRaw) ?? .annuity }
        set { scheduleTypeRaw = newValue.rawValue }
    }

    var frequency: LoanPaymentFrequency {
        get { LoanPaymentFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Вход расчётного ядра. Ядро о персистентности не знает.
    var terms: LoanTerms {
        LoanTerms(
            principal: principal,
            annualRatePercent: annualRatePercent,
            termPeriods: termPeriods,
            firstPaymentDate: firstPaymentDate,
            scheduleType: scheduleType,
            frequency: frequency,
            paymentOverride: paymentOverride
        )
    }

    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "LoanContract",
            "id": id.uuidString,
            "accountID": accountID.uuidString,
            "principal": "\(principal)",
            "annualRatePercent": "\(annualRatePercent)",
            "termPeriods": termPeriods,
            "firstPaymentDate": firstPaymentDate.timeIntervalSince1970,
            "scheduleTypeRaw": scheduleTypeRaw,
            "frequencyRaw": frequencyRaw,
            "paymentsMade": paymentsMade,
            "paidInterestTotal": "\(paidInterestTotal)",
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
        ]
        if let paymentOverride { dict["paymentOverride"] = "\(paymentOverride)" }
        if let insuranceAmount { dict["insuranceAmount"] = "\(insuranceAmount)" }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    /// Импорт идёт через `ModelTypeRegistry` отдельным импортёром (Ф7) — как у `AccountAppearance`.
    static func `import`(_ data: Data) throws {}
}
