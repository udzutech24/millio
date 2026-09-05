//
//  CashflowViewModel+PlannedNotice.swift
//  millio
//
//  Резолверы для сводки применённых плановых операций (Ф1 плана
//  plans/2026-09-05__planned-operations-applied-notice.md). Вынесены из VM отдельным файлом:
//  `CashflowScheduledService` не имеет доступа ни к счетам, ни к отображаемым именам категорий.
//

import Foundation
import SwiftData

extension CashflowViewModel {

    /// Имя счёта операции. Поле `cardID` — общее для двух миров данных: там может лежать как
    /// `Card.cardUniqueID` (легаси), так и `Account.id.uuidString` (новое ядро), поэтому ищем в обоих.
    func plannedNoticeAccountName(for transaction: CashflowTransaction) -> String {
        if let cardID = transaction.cardID, !cardID.isEmpty {
            if let card = card(for: cardID) {
                return card.name
            }
            if let accountID = UUID(uuidString: cardID) {
                let descriptor = FetchDescriptor<Account>()
                if let account = (try? modelContext.fetch(descriptor))?.first(where: { $0.id == accountID }) {
                    return account.name
                }
            }
        }
        if let investmentID = transaction.investmentID, let investment = investment(for: investmentID) {
            return investment.name
        }
        return ""
    }

    /// Заголовок строки сводки. Заметка — тем же правилом, что в истории операций (пользователь
    /// уже видит там ровно этот текст), но при пустой заметке подставляем категорию: обезличенное
    /// «Расход» в сводке ни о чём не говорит.
    func plannedNoticeTitle(for transaction: CashflowTransaction) -> String {
        let trimmedNote = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedNote.isEmpty {
            return cashflowHistoryPrimaryTitle(for: transaction)
        }

        let categoryName: String
        switch transaction.transactionType {
        case .income:
            categoryName = incomeCategoryDisplayName(for: transaction.incomeCategoryRaw)
        case .expense:
            categoryName = expenseCategoryDisplayName(for: transaction.expenseCategoryRaw)
        default:
            categoryName = ""
        }

        return categoryName.isEmpty ? transaction.transactionType.displayName : categoryName
    }
}
