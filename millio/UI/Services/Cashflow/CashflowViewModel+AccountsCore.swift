//
//  CashflowViewModel+AccountsCore.swift
//  millio
//
//  Интеграция нового ядра счетов (event-sourcing) в Cashflow-пикер (Фаза 1b, риск №3):
//  новые Account должны появляться в выборе счёта наравне со старыми картами.
//

import Foundation
import SwiftData

extension CashflowViewModel {
    /// Активные счета нового ядра, пригодные как цель income/expense/transfer в Cashflow
    /// (только денежные kind — cash/debitCard/bankAccount; вклад/кредит/долг/рынок появятся
    /// своими механизмами в следующих фазах, здесь не участвуют).
    func newCoreAccountsForCashflowPicker() -> [Account] {
        let cashLikeKinds: Set<String> = [
            AccountKind.cash.rawValue, AccountKind.debitCard.rawValue, AccountKind.bankAccount.rawValue
        ]
        let descriptor = FetchDescriptor<Account>()
        guard let accounts = try? modelContext.fetch(descriptor) else { return [] }
        let today = now()
        return accounts.filter { cashLikeKinds.contains($0.kindRaw) && $0.participates(on: today) }
    }

    /// «Избранное» core-счетов (V11). У легаси-карты источник свой — `Card.isFavorite`,
    /// у core-счёта его в схеме `Account` нет и не будет: он живёт в `AccountAppearance`.
    /// Один fetch на построение списка — по строке не запрашиваем.
    func coreAccountFavoriteIDsForCashflowPicker() -> Set<UUID> {
        (try? AccountAppearanceStore(context: modelContext).favoriteAccountIDs()) ?? []
    }
}
