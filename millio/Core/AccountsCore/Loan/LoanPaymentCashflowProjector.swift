import Foundation
import SwiftData

/// Проводка платежа по кредиту в Cashflow: расход на фактически внесённую сумму и — отдельной
/// строкой — страховка по договору.
///
/// Дедуп по паре `importSourceRaw` + `importReferenceKey` — тот же контракт, что у
/// `DepositCashflowProjector`: повторная проекция того же `paymentID` строк не добавляет.
/// Ключ платежа и ключ страховки разные, поэтому одна строка не «съедает» другую.
///
/// Страховка вынесена отдельно сознательно (спека §9.1, решение владельца): внутри суммы платежа
/// она исказила бы и разбивку «тело/проценты», и тело долга — страховая премия долг не гасит.
///
/// `affectsCardBalance: false`: с какого счёта ушли деньги, кредит не знает (экран этого не
/// спрашивает), а тронув баланс, проводка задвоила бы движение по счёту-источнику.
@MainActor
enum LoanPaymentCashflowProjector {
    static let importSource = "loanPayment"

    static func paymentReferenceKey(paymentID: UUID) -> String { paymentID.uuidString }

    static func insuranceReferenceKey(paymentID: UUID) -> String { "\(paymentID.uuidString)#insurance" }

    /// Вставляет недостающие строки платежа и возвращает их число (0 — всё уже спроецировано).
    ///
    /// Контекст НЕ сохраняется: вызывающий (`LoanPaymentRecorder`) закрывает платёж одним `save`
    /// вместе с событием ленты и правкой договора, и его `rollback()` снимает эти строки тоже.
    @discardableResult
    static func project(
        account: Account,
        paymentID: UUID,
        amount: Decimal,
        insuranceAmount: Decimal?,
        date: Date,
        context: ModelContext
    ) throws -> Int {
        var planned: [(key: String, amount: Decimal, category: ExpenseCategory, note: String?)] = []
        if amount > 0 {
            planned.append((
                key: paymentReferenceKey(paymentID: paymentID),
                amount: amount,
                // Категории «кредит» в каталоге нет, а `transfers`/`taxes_fees` соврали бы про смысл
                // расхода. Новых системных категорий эта итерация не заводит (спека §10).
                category: .other,
                note: account.name.isEmpty ? nil : account.name
            ))
        }
        if let insuranceAmount, insuranceAmount > 0 {
            planned.append((
                key: insuranceReferenceKey(paymentID: paymentID),
                amount: insuranceAmount,
                category: .insurance,
                note: insuranceNote(for: account)
            ))
        }
        guard !planned.isEmpty else { return 0 }

        let existingKeys = Set(
            try context.fetch(FetchDescriptor<CashflowTransaction>())
                .filter { $0.importSourceRaw == importSource }
                .compactMap(\.importReferenceKey)
        )
        let pending = planned.filter { !existingKeys.contains($0.key) }
        guard !pending.isEmpty else { return 0 }

        // Закрытый месяц отбивается ДО первой вставки: иначе платёж записал бы половину проводки.
        try CashflowMonthMutationPolicy(modelContext: context).validate(.scheduledApply, date: date)

        for row in pending {
            context.insert(CashflowTransaction(
                transactionType: .expense,
                amount: NSDecimalNumber(decimal: row.amount).doubleValue,
                currency: account.currency,
                transactionDate: date,
                expenseCategory: row.category,
                note: row.note,
                importSourceRaw: importSource,
                importReferenceKey: row.key,
                affectsCardBalance: false
            ))
        }
        return pending.count
    }

    private static func insuranceNote(for account: Account) -> String {
        let label = L("accounts_core.loan.cashflow.insurance_note")
        return account.name.isEmpty ? label : "\(label) · \(account.name)"
    }
}
