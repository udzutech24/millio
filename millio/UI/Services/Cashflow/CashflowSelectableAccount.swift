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
        linkedInvestmentIDs: Set<String>,
        transactionType: CashflowTransactionType,
        currency: String,
        newCoreAccounts: [Account] = []
    ) -> [CashflowSelectableAccount] {
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let restrictInvestmentsToFinances = !linkedInvestmentIDs.isEmpty

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
        // Счета нового ядра event-sourcing (Фаза 1a) — та же `.card`-ветка `Kind` (cardID у
        // транзакции = account.id.uuidString, см. AccountsCoreCashflowBridge.resolveNewCoreAccount),
        // без собственного picker-favorite/priority — сортируются по order/createdAt как остальные.
        let newCoreOptions = newCoreAccounts.map {
            CashflowSelectableAccount(
                kind: .card(cardID: $0.id.uuidString),
                title: $0.name,
                currency: $0.currency,
                isFavorite: false,
                prioritySortOrder: $0.order,
                updatedAt: $0.createdAt
            )
        }
        let cardOptionsCombined = cardOptions + newCoreOptions

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
                guard restrictInvestmentsToFinances, let investmentID = option.investmentID else { return true }
                return linkedInvestmentIDs.contains(investmentID)
            }

        let combinedOptions: [CashflowSelectableAccount]
        switch transactionType {
        case .income:
            combinedOptions = cardOptionsCombined + investmentOptions
        case .expense:
            combinedOptions = cardOptionsCombined + investmentOptions
        case .transfer:
            combinedOptions = cardOptionsCombined
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
