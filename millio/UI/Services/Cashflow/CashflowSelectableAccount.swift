//
//  CashflowSelectableAccount.swift
//  millio
//

import Foundation

struct CashflowSelectableAccount: Identifiable, Equatable {
    enum Kind: Equatable {
        case card(cardID: String)
        case investment(investmentID: String)
    }

    let kind: Kind
    let title: String
    let currency: String
    let isFavorite: Bool
    let prioritySortOrder: Int
    let updatedAt: Date

    var pickerTitle: String {
        isFavorite ? "★ \(title)" : title
    }

    var id: String {
        switch kind {
        case .card(let cardID):
            return "card:\(cardID)"
        case .investment(let investmentID):
            return "investment:\(investmentID)"
        }
    }

    var cardID: String? {
        guard case .card(let cardID) = kind else { return nil }
        return cardID
    }

    var investmentID: String? {
        guard case .investment(let investmentID) = kind else { return nil }
        return investmentID
    }
}

enum CashflowSelectableAccountResolver {
    static func options(
        cards: [Card],
        investments: [Investment],
        financeAccounts: [FinanceAccount],
        transactionType: CashflowTransactionType,
        currency: String
    ) -> [CashflowSelectableAccount] {
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let linkedCardIDs = Set(financeAccounts.compactMap { account in
            account.accountType == .card ? account.accountID : nil
        })
        let linkedInvestmentIDs = Set(financeAccounts.compactMap { account in
            account.accountType == .investment ? account.accountID : nil
        })
        let restrictToFinances = !financeAccounts.isEmpty

        let cardOptions = cards.map {
            CashflowSelectableAccount(
                kind: .card(cardID: $0.cardUniqueID),
                title: $0.name,
                currency: $0.currency,
                isFavorite: $0.isFavorite,
                prioritySortOrder: $0.priority.sortOrder,
                updatedAt: $0.updatedAt
            )
        }
        .filter { option in
            guard restrictToFinances, let cardID = option.cardID else { return true }
            return linkedCardIDs.contains(cardID)
        }

        let investmentOptions = investments
            .filter(\.isCashflowAccount)
            .map {
                CashflowSelectableAccount(
                    kind: .investment(investmentID: $0.investmentUniqueID),
                    title: $0.name,
                    currency: $0.currency,
                    isFavorite: $0.isFavorite,
                    prioritySortOrder: $0.priority.sortOrder,
                    updatedAt: $0.updatedAt
                )
            }
            .filter { option in
                guard restrictToFinances, let investmentID = option.investmentID else { return true }
                return linkedInvestmentIDs.contains(investmentID)
            }

        let combinedOptions: [CashflowSelectableAccount]
        switch transactionType {
        case .income:
            combinedOptions = cardOptions + investmentOptions
        case .expense, .transfer:
            combinedOptions = cardOptions
        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            combinedOptions = []
        }

        let filteredOptions: [CashflowSelectableAccount]
        if transactionType == .income || transactionType == .expense {
            if normalizedCurrency.isEmpty {
                filteredOptions = combinedOptions
            } else {
                filteredOptions = combinedOptions.filter {
                    $0.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCurrency
                }
            }
        } else {
            filteredOptions = combinedOptions
        }

        return filteredOptions.sorted { lhs, rhs in
            if lhs.prioritySortOrder != rhs.prioritySortOrder {
                return lhs.prioritySortOrder < rhs.prioritySortOrder
            }
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

extension Investment {
    var isCashflowAccount: Bool {
        investmentType == .positive
            && category == .other
            && !isMarketPriced
    }
}
