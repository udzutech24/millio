import Foundation
import SwiftData

/// Мост «старый флоу добавления счёта → новое ядро event-sourcing» (Фаза 1a-ui).
/// Пресеты «Карта» и «Счёт» создают `Account` нового ядра вместо `Card`/`Investment`.
/// Остальные 9 пресетов (вклад/кредит/долг/акции/крипта/недвижимость/бизнес/…) остаются
/// на старом пути — их перенос запланирован в фазах 2–4 (план `2026-07-04__accounts-core-rebuild-plan.md`).
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
}
