import Foundation
import SwiftData

/// Мост «старый флоу добавления счёта → новое ядро event-sourcing» (Фаза 1a-ui, 2).
/// Пресеты «Карта»/«Счёт» (Фаза 1a) и «Кредит»/«Долг» (Фаза 2) создают `Account` нового ядра
/// вместо `Card`/`Credit`/`Investment`. Остальные 7 пресетов (вклад/акции/крипта/недвижимость/
/// бизнес/…) остаются на старом пути — перенос запланирован в фазах 3–4 (план `2026-07-04__accounts-core-rebuild-plan.md`).
enum AccountsCoreAdditionBridge {

    /// kind для денежного пресета «Карта»: пустой/невыбранный банк (`.other`) трактуется как
    /// наличка без банка (спека §2.7, п. 63 — «наличка — вариант карты без банка»).
    /// Это временная эвристика до появления отдельного UI-пресета «Наличка».
    static func cardKind(bank: Bank) -> AccountKind {
        bank == .other ? .cash : .debitCard
    }

    /// Находит `AccountGroup` с тем же именем, что у выбранной `FinanceGroup`, либо создаёт новую.
    /// ВРЕМЕННЫЙ мэппинг по имени (до Фазы 6, когда группы старого/нового мира объединятся в одну
    /// сущность) — см. спеку §2.7 и план, раздел «Фаза 6». `nil` (счёт без группы = Ungrouped)
    /// не создаёт AccountGroup — совпадает с семантикой Ungrouped нового ядра (`account.group == nil`).
    static func resolveAccountGroup(matching financeGroup: FinanceGroup?, in modelContext: ModelContext) -> AccountGroup? {
        guard let financeGroup else { return nil }
        let targetName = financeGroup.name

        let descriptor = FetchDescriptor<AccountGroup>(
            predicate: #Predicate<AccountGroup> { $0.name == targetName }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let newGroup = AccountGroup(name: targetName, colorHex: financeGroup.colorHex)
        modelContext.insert(newGroup)
        return newGroup
    }

    /// Мэппинг формы «Кредит» старого мира → `LoanMeta` (Фаза 2). Старая форма НЕ собирает
    /// процентную ставку (`Credit.interestRate` всегда 0 при создании, см. `CreditViewModel.updateCredit`) —
    /// сохраняем этот же пробел (0), а не придумываем поле задним числом: schedule/rate UI — Фаза 3.
    /// `scheduleType` тоже не собирается формой — дефолт `.annuity` не используется расчётами в скоупе M
    /// (график погашения — вне скоупа), это просто безопасное значение по умолчанию.
    static func loanMeta(
        principal: Decimal,
        monthlyPayment: Decimal?,
        paymentDay: Int?,
        termEnd: Date?
    ) -> LoanMeta {
        LoanMeta(
            principal: principal,
            rate: 0,
            monthlyPayment: monthlyPayment,
            paymentDay: paymentDay,
            termEnd: termEnd,
            scheduleType: .annuity,
            insurance: nil
        )
    }

    /// Мэппинг формы «Долг» старого мира (Investment.category == .debt) → `DebtMeta`. Направление
    /// берётся из существующего `InvestmentType` (.positive = мне должны, .negative = я должен) —
    /// это ЕДИНСТВЕННОЕ поле направления, которое собирает старая форма. Контрагент/срок возврата
    /// старая форма не собирает вовсе (нет UI-поля) — оставляем nil, а не редизайним форму (вне скоупа).
    static func debtMeta(direction: DebtDirection) -> DebtMeta {
        DebtMeta(direction: direction, counterparty: nil, dueDate: nil, rate: nil)
    }
}
