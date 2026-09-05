import Foundation
import SwiftData

/// Приведение остатка долга в ленте счёта к сумме кредита из договора (спека Р6).
///
/// Остаток живёт в `AccountEvent`, сумма кредита — в `LoanContract`, и обычно это РАЗНЫЕ числа:
/// остаток уменьшают платежи. Но пока по договору не внесено ни одного платежа, других причин для
/// расхождения нет — сумма кредита и есть остаток. Поэтому правка суммы на экране условий в этом
/// (и только в этом) случае догоняет ленту одним корректирующим событием.
///
/// Своего пути записи здесь нет: событие пишет `AccountsCoreService.recordEvent` — та же точка,
/// через которую идут платежи (`LoanPaymentRecorder`), с её `saveOrRollback`.
@MainActor
struct LoanPrincipalCorrection {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Корректирующее событие либо `nil`, если ленту трогать нельзя или уже нечего.
    ///
    /// - `paymentsMade > 0` — остаток уже результат операций, правка условий его не переписывает.
    /// - расхождение меньше копейки — это пыль `Decimal` от double-хранения, а не долг
    ///   (тот же порог, что в `LoanOutstanding`).
    @discardableResult
    func alignOutstanding(
        account: Account,
        to principal: Decimal,
        paymentsMade: Int,
        date: Date = Date()
    ) throws -> AccountEvent? {
        guard account.kind == .loan else { throw LoanPaymentError.notALoanAccount }
        guard paymentsMade == 0, principal > 0 else { return nil }

        let outstanding = LoanOutstanding.fromLedger(
            balance: AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: date)
        )
        let delta = principal - outstanding
        guard abs(delta) >= Decimal(1) / 100 else { return nil }

        // Знак задаёт движок C: `.expense` увеличивает долг, `.income` уменьшает — сумма всегда
        // положительная, как во всех операциях кредита.
        return try AccountsCoreService(modelContext: modelContext).recordEvent(
            account: account,
            type: delta > 0 ? .expense : .income,
            amount: abs(delta),
            date: date,
            note: L("accounts_core.loan_form.principal_correction_note")
        )
    }
}
