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
/// Расход в Cashflow пишет `LoanPaymentCashflowProjector` — здесь же, одной транзакцией с событием
/// и договором (спека §9.1). Дедупликация — его забота, ключом служит `paymentID` этой операции.
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
        note: String? = nil,
        cashflowReferenceKey: String? = nil
    ) throws -> AccountEvent {
        guard account.kind == .loan else { throw LoanPaymentError.notALoanAccount }
        guard principalPart > 0 else { throw LoanPaymentError.nonPositivePrincipalPart }

        let entry = LoanExtraPaymentEntry(
            principalPart: principalPart,
            interestPart: interestPart,
            consumesPeriod: true,
            pinnedPayment: nil
        )
        guard let event = try record(
            entry,
            on: account,
            date: date,
            note: note,
            cashflowReferenceKey: cashflowReferenceKey
        ) else {
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
        note: String? = nil,
        cashflowReferenceKey: String? = nil
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

        // Расход идёт ПЕРВЫМ шагом: закрытый месяц Cashflow должен отбить платёж целиком, пока в
        // контексте ещё ничего не изменено. Сумма — фактически внесённая (тело + проценты, после
        // клампа по остатку), а не запрошенная: в Cashflow попадает то, что реально ушло из кармана.
        try LoanPaymentCashflowProjector.project(
            account: account,
            referenceKey: cashflowReferenceKey
                ?? LoanPaymentCashflowProjector.paymentReferenceKey(paymentID: UUID()),
            amount: principalPart + max(entry.interestPart, 0),
            date: date,
            context: modelContext
        )

        // Порядок важен: договор правится ДО записи события. `recordEvent` — единственная точка
        // сохранения, и её `rollback()` при ошибке снимает вместе с событием и эти правки —
        // так «одна транзакция» получается без второго save-барьера.
        try LoanContractStore(context: modelContext).upsert(accountID: account.id) { contract in
            if entry.consumesPeriod { contract.paymentsMade += 1 }
            contract.paidInterestTotal += max(entry.interestPart, 0)
            if let pinned = entry.pinnedPayment, pinned > 0 { contract.paymentOverride = pinned }
        }

        guard principalPart > 0 else {
            // Договор и строки Cashflow изменились, а события нет — сохраняем сами: `recordEvent`
            // в этой ветке не вызывается, и без save правки остались бы только в памяти контекста.
            try modelContext.save()
            syncPlannedPayment(accountID: account.id)
            return nil
        }

        let event = try AccountsCoreService(modelContext: modelContext).recordEvent(
            account: account,
            type: .income,
            amount: principalPart,
            date: date,
            note: note
        )
        syncPlannedPayment(accountID: account.id)
        return event
    }

    /// Пересчёт плановой операции ПОСЛЕ записи платежа: до события остаток в ленте ещё старый, и
    /// план встал бы на тот же период с той же суммой (`LoanContractStore.upsert` внутри платежа
    /// синхронизирует именно такое промежуточное состояние — этот вызов его исправляет).
    ///
    /// Ошибка синхронизации плана не роняет платёж: он уже сохранён, бросать после сохранения
    /// нечего. Инвариант «ровно одна плановая операция» восстановится при следующем касании
    /// договора; расхождение попадает в лог.
    private func syncPlannedPayment(accountID: UUID) {
        do {
            try LoanPlannedPaymentScheduler.sync(accountID: accountID, context: modelContext)
            try modelContext.save()
        } catch {
            AppLogger.log(
                .error,
                category: "AccountsCore",
                "Failed to sync loan planned payment: \(error.localizedDescription)"
            )
        }
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
