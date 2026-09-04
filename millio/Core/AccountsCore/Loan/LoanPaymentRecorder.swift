import Foundation
import SwiftData

/// Внесение платежа по кредиту: событие в ленте счёта + прогресс договора одной транзакцией.
///
/// Долг уменьшает ТОЛЬКО тело платежа: проценты — плата за пользование деньгами, остаток по ним не
/// падает (спека Р6). Поэтому в ленту уходит событие на сумму тела, а проценты копятся в
/// `LoanContract.paidInterestTotal` и в балансе счёта не участвуют.
///
/// Единственный путь записи для всех операций кредита: плановый платёж (Ф4), досрочное погашение и
/// недоплата (Ф6). Второй путь развёл бы правила «что уменьшает долг» по экранам.
///
/// Проводка расхода в Cashflow — не здесь: она появится в Ф7 (спека §9.1) и обязана быть
/// дедуплицируемой, чего у события счёта нет.
@MainActor
struct LoanPaymentRecorder {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Плановый платёж по графику. Суммы приходят НЕокруглёнными — так же, как их считает ядро
    /// (контракт округления §4.3). Округлив тело при записи, мы уводили бы ленту с графика на
    /// копейки каждый платёж, и через полсотни периодов остаток на экране перестал бы сходиться.
    ///
    /// Тело обязано быть положительным: платёж, которого не хватает даже на проценты, — это уже
    /// недоплата, и она идёт через `record(_:on:)` с собственными правилами.
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

        let entry = LoanExtraPaymentEntry(
            principalPart: principalPart,
            interestPart: interestPart,
            consumesPeriod: true,
            pinnedPayment: nil
        )
        guard let event = try record(entry, on: account, date: date, note: note) else {
            // Недостижимо: тело положительное, значит событие создаётся всегда.
            throw LoanPaymentError.nonPositivePrincipalPart
        }
        return event
    }

    /// Внеплановая сумма: досрочное погашение или недоплата. Что уходит в тело, что в проценты и
    /// расходуется ли период графика — решает ядро (`LoanPrepaymentPlanner`), не экран.
    ///
    /// Возвращает `nil`, когда тела в операции нет: недоплата, которой не хватило даже на проценты
    /// периода, договор двигает, а ленту — нет.
    @discardableResult
    func record(
        _ entry: LoanExtraPaymentEntry,
        on account: Account,
        date: Date = Date(),
        note: String? = nil
    ) throws -> AccountEvent? {
        guard account.kind == .loan else { throw LoanPaymentError.notALoanAccount }
        guard entry.principalPart >= 0 else { throw LoanPaymentError.nonPositivePrincipalPart }

        // Больше остатка внести нельзя: иначе долг ушёл бы в плюс и счёт-обязательство стал бы
        // активом в net worth. Клампим здесь, а не на экране, — инвариант ленты, а не оформления.
        let outstanding = max(
            -AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: date),
            .zero
        )
        let principalPart = min(entry.principalPart, outstanding)

        // Порядок важен: договор правится ДО записи события. `recordEvent` — единственная точка
        // сохранения, и её `rollback()` при ошибке снимает вместе с событием и эти правки —
        // так «одна транзакция» получается без второго save-барьера.
        try LoanContractStore(context: modelContext).upsert(accountID: account.id) { contract in
            if entry.consumesPeriod { contract.paymentsMade += 1 }
            contract.paidInterestTotal += max(entry.interestPart, 0)
            if let pinned = entry.pinnedPayment, pinned > 0 { contract.paymentOverride = pinned }
        }

        guard principalPart > 0 else {
            // Договор изменился, а события нет — сохраняем сами: `recordEvent` в этой ветке не
            // вызывается, и без save правка осталась бы только в памяти контекста.
            try modelContext.save()
            return nil
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
