//
//  FinanceNetWorthSignedAmount.swift
//  millio
//
//  Единая логика знака "вклад в итого" (net worth) для разных типов финансовых продуктов.
//
//  Правило:
//  - то, что УВЕЛИЧИВАЕТ итоговую сумму -> положительный знак (debit)
//  - то, что УМЕНЬШАЕТ итоговую сумму -> отрицательный знак (credit)
//
//  Важно:
//  UI может отображать обязательства как положительное число (величину долга),
//  но для бухгалтерской раскладки нам нужен именно знак вклада в общий итог.
//

import Foundation

enum FinanceNetWorthSignedAmount {
    static func signedValue(
        for account: FinanceAccount,
        cardsByID: [String: Card],
        creditsByID: [String: Credit],
        investmentsByID: [String: Investment],
        epsilon: Double = 0.01
    ) -> Double? {
        switch account.accountType {
        case .card:
            guard let card = cardsByID[account.accountID] else { return nil }
            return signedValue(for: card, epsilon: epsilon)
        case .credit:
            guard let credit = creditsByID[account.accountID] else { return nil }
            return signedValue(for: credit, epsilon: epsilon)
        case .investment:
            guard let investment = investmentsByID[account.accountID] else { return nil }
            return signedValue(for: investment, epsilon: epsilon)
        }
    }

    static func signedValue(for card: Card, epsilon: Double = 0.01) -> Double? {
        guard card.archivedAt == nil else { return nil }
        guard card.includeInTotal else { return nil }

        if card.cardType == .credit, let limit = card.creditLimit {
            let debt = max(0, limit - card.balance)
            guard debt > epsilon else { return nil }
            return -debt
        }

        guard abs(card.balance) > epsilon else { return nil }
        return card.balance
    }

    static func signedValue(for credit: Credit, epsilon: Double = 0.01) -> Double? {
        guard credit.archivedAt == nil else { return nil }
        guard credit.includeInTotal else { return nil }
        guard credit.remainingAmount > epsilon else { return nil }
        return -credit.remainingAmount
    }

    static func signedValue(for investment: Investment, epsilon: Double = 0.01) -> Double? {
        guard investment.archivedAt == nil else { return nil }
        guard investment.includeInTotal else { return nil }
        guard investment.amount > epsilon else { return nil }

        switch investment.investmentType {
        case .positive:
            return investment.amount
        case .negative:
            return -investment.amount
        }
    }
}

