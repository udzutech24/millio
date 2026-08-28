//
//  CashflowViewModel+AccountPicker.swift
//  millio
//

import Foundation
import SwiftData

extension CashflowViewModel {
    /// Иконки и «доступно к трате» для строк пикера счёта.
    /// Асинхронно и с уступкой потока: баланс core-счёта — реплей всех его событий, при
    /// нескольких десятках счетов синхронный расчёт в `body` подвесил бы шит.
    /// Не резолвится счёт — в словарь ничего не кладём: пикер покажет прочерк, а не «0».
    func accountPickerDetails(
        for accounts: [CashflowSelectableAccount]
    ) async -> [String: CashflowAccountPickerDetails] {
        let today = now()
        var result: [String: CashflowAccountPickerDetails] = [:]

        for (index, account) in accounts.enumerated() {
            if index > 0, index.isMultiple(of: 10) {
                await Task.yield()
            }

            switch account.kind {
            case .legacyCard(let cardID):
                if let card = card(for: cardID) {
                    result[account.id] = CashflowAccountPickerDetailsFactory.details(for: card)
                }
            case .coreAccount(let accountID):
                if let coreAccount = coreAccountForPicker(id: accountID) {
                    let balance = AccountBalanceEngine.balanceAt(
                        events: coreAccount.events ?? [],
                        kind: coreAccount.kind,
                        on: today
                    )
                    result[account.id] = CashflowAccountPickerDetailsFactory.details(
                        for: coreAccount,
                        balance: balance
                    )
                }
            case .investment(let investmentID):
                if let investment = investment(for: investmentID) {
                    result[account.id] = CashflowAccountPickerDetailsFactory.details(for: investment)
                }
            }
        }

        return result
    }

    private func coreAccountForPicker(id: String) -> Account? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
