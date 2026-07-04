import Foundation

/// Настройки налога на проценты по вкладам — «реальный доход чистыми» (план §2.8, брифинг Фазы 3).
/// Хранятся ПО ЧЕЛОВЕКУ в `SettingsManager` (UserDefaults), НЕ у счёта: НДФЛ на проценты считается
/// за календарный год по сумме ВСЕХ вкладов, а не по одному счёту.
struct DepositTaxSettings: Equatable {
    /// Ставка НДФЛ, ЧИСЛОМ-ПРОЦЕНТОМ (13 = 13%) — та же конвенция, что у `DepositMeta.rate`.
    var ndflRatePercent: Decimal
    /// Максимальная ключевая ставка ЦБ за календарный год — ДОЛЯ (0.16 = 16%), не процент.
    /// Нет авто-источника курса в Фазе 3— задаётся вручную (док брифинга п.4).
    var keyRateForYear: Decimal

    static let `default` = DepositTaxSettings(ndflRatePercent: 13, keyRateForYear: 0.16)
}

/// Доля общего налога за год, отнесённая на один вклад (для показа «чистыми» на карточке этого счёта).
struct DepositTaxAllocation: Equatable {
    let accountID: UUID
    /// Σ interest-событий ЭТОГО вклада за год (уже в ₽).
    let grossInterestRUB: Decimal
    /// Доля превышения лимита, пропорционально отнесённая на этот вклад.
    let allocatedExcessRUB: Decimal
    /// Налог, отнесённый на этот вклад.
    let allocatedTaxRUB: Decimal
}

struct DepositTaxResult: Equatable {
    let year: Int
    let totalGrossInterestRUB: Decimal
    let taxFreeLimitRUB: Decimal
    let taxableExcessRUB: Decimal
    let totalTaxRUB: Decimal
    let perAccount: [DepositTaxAllocation]
}

/// Расчёт налога «чистыми» на проценты по вкладам (спека §2.8). Pure — не читает SwiftData и не знает
/// про FX: вызывающий код обязан сконвертировать проценты валютных вкладов в ₽ курсом ДАТЫ СОБЫТИЯ
/// ДО вызова (брифинг Фазы 3, п.4) — лимит и налог всегда считаются в ₽, независимо от primaryCurrency.
///
/// НДФЛ на проценты по вкладам считается ПО ЧЕЛОВЕКУ за календарный год, а не по счёту: лимит
/// = 1 000 000 ₽ × макс. ключевая ставка ЦБ за год; налог берётся с суммы процентов по ВСЕМ вкладам,
/// превышающей лимит, затем распределяется по вкладам ПРОПОРЦИОНАЛЬНО их доле в ОБЩЕЙ сумме
/// процентов (не в "свой" лимит — лимит один общий на всех).
enum DepositTaxCalculator {

    /// Одно interest-событие одного вклада за год, УЖЕ сконвертированное в ₽.
    struct InterestEventInput {
        let accountID: UUID
        let amountRUB: Decimal
    }

    static func calculate(
        interestEventsInRUB: [InterestEventInput],
        year: Int,
        settings: DepositTaxSettings
    ) -> DepositTaxResult {
        let taxFreeLimit = round2(1_000_000 * settings.keyRateForYear)
        let totalGross = interestEventsInRUB.reduce(Decimal(0)) { $0 + $1.amountRUB }

        guard totalGross > 0 else {
            return DepositTaxResult(
                year: year, totalGrossInterestRUB: 0, taxFreeLimitRUB: taxFreeLimit,
                taxableExcessRUB: 0, totalTaxRUB: 0, perAccount: []
            )
        }

        let excess = max(0, totalGross - taxFreeLimit)
        let totalTax = round2(excess * settings.ndflRatePercent / 100)

        var grossByAccount: [UUID: Decimal] = [:]
        for event in interestEventsInRUB {
            grossByAccount[event.accountID, default: 0] += event.amountRUB
        }

        let perAccount = grossByAccount.map { accountID, gross -> DepositTaxAllocation in
            let share = gross / totalGross
            let allocatedExcess = round2(excess * share)
            let allocatedTax = round2(allocatedExcess * settings.ndflRatePercent / 100)
            return DepositTaxAllocation(
                accountID: accountID,
                grossInterestRUB: gross,
                allocatedExcessRUB: allocatedExcess,
                allocatedTaxRUB: allocatedTax
            )
        }.sorted { $0.grossInterestRUB > $1.grossInterestRUB }

        return DepositTaxResult(
            year: year,
            totalGrossInterestRUB: totalGross,
            taxFreeLimitRUB: taxFreeLimit,
            taxableExcessRUB: excess,
            totalTaxRUB: totalTax,
            perAccount: perAccount
        )
    }

    /// Округление до копейки — ОБЫЧНОЕ (`.plain`), см. `DepositInterestScheduler.round2` (тот же выбор).
    private static func round2(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var mutable = value
        NSDecimalRound(&result, &mutable, 2, .plain)
        return result
    }
}
