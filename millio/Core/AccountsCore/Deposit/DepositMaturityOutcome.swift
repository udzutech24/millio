import Foundation

/// Итог «что дальше» для вклада с вышедшим сроком: сколько лежит на вкладе, сколько из этого
/// проценты и сколько налога за год отнесено на этот вклад. Считается из готового снапшота и
/// готовой налоговой аллокации — своих формул не заводит.
struct DepositMaturityOutcome: Equatable, Sendable {
    let currency: String
    /// То, что реально переведём на выбранный счёт — подтверждённый баланс вклада.
    let payoutAmount: Decimal
    /// Проценты, подтверждённые за срок (уже входят в `payoutAmount`).
    let accruedInterest: Decimal
    /// Налог за календарный год, отнесённый на этот вклад. Всегда в ₽ — так его и считает
    /// `DepositTaxCalculator` (лимит НДФЛ рублёвый). `nil` — посчитать нечем.
    let estimatedTaxRUB: Decimal?
    /// Сумма к получению за вычетом налога. Только для рублёвого вклада: вычитать рублёвый налог
    /// из валютной суммы нельзя — курса дня выплаты здесь нет, и цифра получилась бы выдуманной.
    let netPayout: Decimal?

    static func make(
        snapshot: DepositPresentationSnapshot,
        taxAllocation: DepositTaxAllocation?
    ) -> DepositMaturityOutcome? {
        guard let payout = snapshot.currentBalance.value else { return nil }
        let tax = taxAllocation.map { max(0, $0.allocatedTaxRUB) }
        let isRUB = snapshot.currency.uppercased() == "RUB"
        return DepositMaturityOutcome(
            currency: snapshot.currency,
            payoutAmount: payout,
            accruedInterest: max(0, snapshot.confirmedInterest.value ?? 0),
            estimatedTaxRUB: tax,
            netPayout: isRUB ? tax.map { max(0, payout - $0) } : nil
        )
    }
}
