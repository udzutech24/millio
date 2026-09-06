import SwiftUI
import SwiftData

/// Обязательства (`.loan` / `.debt`): строки инфо на hero и подписи действий под знак долга.
extension AccountDetailView {
    // MARK: - Обязательства (.loan/.debt) — доп. инфо и кастомные действия (Фаза 2)

    /// Условия кредита — только через `LoanTermsResolver` (спека Р5): договор V12, иначе сид из
    /// легаси `LoanMeta`. Прямого чтения `account.loanMeta` здесь быть не должно, иначе договор и
    /// мета разъедутся у одного и того же счёта.
    var loanInfoLines: [String]? {
        guard let terms = LoanTermsResolver.terms(for: account, contract: loanContract) else { return nil }
        var lines: [String] = []
        if terms.annualRatePercent > 0 {
            lines.append(String(format: L("accounts_core.detail.loan.rate_format"), NSDecimalNumber(decimal: terms.annualRatePercent).doubleValue))
        }
        if let payment = LoanScheduleEngine.regularPayment(terms: terms), payment > 0 {
            let rounded = DepositInterestScheduler.round2(payment)
            lines.append(String(format: L("accounts_core.detail.loan.monthly_payment_format"), NSDecimalNumber(decimal: rounded).doubleValue, account.currency))
        }
        // Срок известен только когда он задан в периодах: график с ручным платежом и без срока
        // открытый, и дату закрытия здесь считать нечем (её показывает деталка кредита, Ф4).
        if terms.termPeriods > 0,
           let termEnd = LoanScheduleEngine.paymentDate(period: terms.termPeriods, terms: terms) {
            lines.append(String(format: L("accounts_core.detail.loan.term_end_format"), termEnd.formatted(date: .abbreviated, time: .omitted)))
        }
        return lines.isEmpty ? nil : lines
    }

    var debtInfoLines: [String]? {
        guard let meta = account.debtMeta else { return nil }
        var lines: [String] = [
            meta.direction == .owedToMe
                ? L("accounts_core.detail.debt.direction.owed_to_me")
                : L("accounts_core.detail.debt.direction.owed_by_me")
        ]
        if let counterparty = meta.counterparty, !counterparty.isEmpty {
            lines.append(String(format: L("accounts_core.detail.debt.counterparty_format"), counterparty))
        }
        if let dueDate = meta.dueDate {
            lines.append(String(format: L("accounts_core.detail.debt.due_date_format"), dueDate.formatted(date: .abbreviated, time: .omitted)))
        }
        return lines
    }

    /// Заголовок кнопки «доход»-слота — для обязательств это «Платёж»/«Погашение», не «Доход».
    var incomeActionTitle: String {
        switch account.kind {
        case .loan: return L("accounts_core.detail.action.payment")
        case .debt: return L("accounts_core.detail.action.repay")
        default: return L("accounts_core.detail.action.add_income")
        }
    }

    /// Заголовок кнопки «расход»-слота — для обязательств это «Увеличить долг»/«Увеличить».
    var expenseActionTitle: String {
        switch account.kind {
        case .loan: return L("accounts_core.detail.action.increase_debt")
        case .debt: return L("accounts_core.detail.action.increase")
        default: return L("accounts_core.detail.action.add_expense")
        }
    }

    /// `.loan` использует собственный движок (loanSignMap) — income ВСЕГДА уменьшает долг,
    /// вне зависимости от направления. `.debt` использует ленту генерик-движка (как cash) —
    /// направление знака зависит от того, кому должны: owedToMe требует ПРОТИВОПОЛОЖНОГО типа
    /// события, чтобы «погашение» всегда уменьшало |баланс| (см. брифинг Фазы 2, п.2).
    var incomeSheetEventType: AccountEventType {
        guard account.kind == .debt, account.debtMeta?.direction == .owedToMe else { return .income }
        return .expense
    }

    var expenseSheetEventType: AccountEventType {
        guard account.kind == .debt, account.debtMeta?.direction == .owedToMe else { return .expense }
        return .income
    }
}
