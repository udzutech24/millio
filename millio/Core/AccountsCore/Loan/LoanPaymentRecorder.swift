import Foundation
import SwiftData

/// Внесение планового платежа по кредиту: событие в ленте счёта + прогресс договора одной транзакцией.
///
/// Долг уменьшает ТОЛЬКО тело платежа: проценты — плата за пользование деньгами, остаток по ним не
/// падает (спека Р6). Поэтому в ленту уходит событие на сумму тела, а проценты копятся в
/// `LoanContract.paidInterestTotal` и в балансе счёта не участвуют.
///
/// Проводка расхода в Cashflow — не здесь: она появится в Ф7 (спека §9.1) и обязана быть
/// дедуплицируемой, чего у события счёта нет.
@MainActor
struct LoanPaymentRecorder {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Суммы приходят НЕокруглёнными — так же, как их считает ядро (контракт округления §4.3).
    /// Округлив тело при записи, мы уводили бы ленту с графика на копейки каждый платёж, и через
    /// полсотни периодов остаток на экране перестал бы сходиться с графиком.
    @discardableResult
    func recordScheduledPayment(
        account: Account,
        principalPart: Decimal,
        interestPart: Decimal,
        date: Date = Date(),
        note: String? = nil
    ) throws -> AccountEvent {
        guard account.kind == .loan else { throw LoanPaymentError.notALoanAccount }
        guard principalPart > 0 else { throw LoanPaymentError.nonPositivePrincipalPart }

        // Порядок важен: договор правится ДО записи события. `recordEvent` — единственная точка
        // сохранения, и её `rollback()` при ошибке снимает вместе с событием и эти правки —
        // так «одна транзакция» получается без второго save-барьера.
        try LoanContractStore(context: modelContext).upsert(accountID: account.id) { contract in
            contract.paymentsMade += 1
            contract.paidInterestTotal += max(interestPart, 0)
        }

        return try AccountsCoreService(modelContext: modelContext).recordEvent(
            account: account,
            type: .income,
            amount: principalPart,
            date: date,
            note: note
        )
    }
}

enum LoanPaymentError: LocalizedError {
    case notALoanAccount
    case nonPositivePrincipalPart

    var errorDescription: String? {
        switch self {
        case .notALoanAccount: L("accounts_core.loan.detail.error.not_a_loan")
        case .nonPositivePrincipalPart: L("accounts_core.loan.detail.error.payment_below_interest")
        }
    }
}
