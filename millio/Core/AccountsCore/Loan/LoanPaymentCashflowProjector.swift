import Foundation
import SwiftData

/// Проводка платежа по кредиту в Cashflow: одна строка расхода на фактически внесённую сумму.
///
/// Дедуп по паре `importSourceRaw` + `importReferenceKey` — тот же контракт, что у
/// `DepositCashflowProjector`: повторная проекция того же `paymentID` строк не добавляет.
///
/// Страховка кредитом не проводится (решение владельца 07.09): это отдельный продукт со своим
/// сроком и своей платёжной датой, и внутри платежа по кредиту она врала бы и про расход, и про
/// разбивку «тело/проценты». Ведут её обычной регулярной операцией Cashflow.
///
/// `affectsCardBalance: false`: с какого счёта ушли деньги, кредит не знает (экран этого не
/// спрашивает), а тронув баланс, проводка задвоила бы движение по счёту-источнику.
@MainActor
enum LoanPaymentCashflowProjector {
    static let importSource = "loanPayment"

    static func paymentReferenceKey(paymentID: UUID) -> String { paymentID.uuidString }

    /// Вставляет строку платежа и возвращает её число (0 — платёж уже спроецирован или пуст).
    ///
    /// Контекст НЕ сохраняется: вызывающий (`LoanPaymentRecorder`) закрывает платёж одним `save`
    /// вместе с событием ленты и правкой договора, и его `rollback()` снимает эту строку тоже.
    @discardableResult
    static func project(
        account: Account,
        paymentID: UUID,
        amount: Decimal,
        date: Date,
        context: ModelContext
    ) throws -> Int {
        guard amount > 0 else { return 0 }
        let key = paymentReferenceKey(paymentID: paymentID)
        let alreadyProjected = try context.fetch(FetchDescriptor<CashflowTransaction>())
            .contains { $0.importSourceRaw == importSource && $0.importReferenceKey == key }
        guard !alreadyProjected else { return 0 }

        // Закрытый месяц отбивается ДО вставки: иначе платёж записал бы половину проводки.
        try CashflowMonthMutationPolicy(modelContext: context).validate(.scheduledApply, date: date)

        context.insert(CashflowTransaction(
            transactionType: .expense,
            amount: NSDecimalNumber(decimal: amount).doubleValue,
            currency: account.currency,
            transactionDate: date,
            // Категории «кредит» в каталоге нет, а `transfers`/`taxes_fees` соврали бы про смысл
            // расхода. Новых системных категорий эта итерация не заводит (спека §10).
            expenseCategory: .other,
            note: account.name.isEmpty ? nil : account.name,
            importSourceRaw: importSource,
            importReferenceKey: key,
            affectsCardBalance: false
        ))
        return 1
    }
}
