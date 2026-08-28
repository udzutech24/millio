//
//  CashflowSelectableAccount.swift
//  millio
//

import Foundation

struct CashflowSelectableAccount: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Легаси-карта, `Card.cardUniqueID`.
        case legacyCard(cardID: String)
        /// Счёт нового ядра, `Account.id.uuidString`. В транзакции лежит в том же поле `cardID`,
        /// но это другой мир данных — поэтому у него отдельный кейс и отдельный префикс `id`:
        /// иначе core-UUID и легаси-ID могут дать одинаковый `id` в `ForEach`.
        case coreAccount(accountID: String)
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
        case .legacyCard(let cardID):
            return "card:\(cardID)"
        case .coreAccount(let accountID):
            return "core:\(accountID)"
        case .investment(let investmentID):
            return "investment:\(investmentID)"
        }
    }

    /// ID, который уходит в поле `CashflowTransaction.cardID` — общее для обоих миров счетов.
    var cardID: String? {
        switch kind {
        case .legacyCard(let id), .coreAccount(let id):
            return id
        case .investment:
            return nil
        }
    }

    var isCoreAccount: Bool {
        if case .coreAccount = kind { return true }
        return false
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
        newCoreAccounts: [Account] = [],
        coreFavoriteAccountIDs: Set<UUID> = []
    ) -> [CashflowSelectableAccount] {
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let restrictInvestmentsToFinances = !linkedInvestmentIDs.isEmpty

        let cardOptions = cards.map {
            CashflowSelectableAccount(
                kind: .legacyCard(cardID: $0.cardUniqueID),
                title: $0.name,
                currency: $0.currency,
                isFavorite: $0.isFavorite,
                prioritySortOrder: $0.priority.sortOrder,
                updatedAt: $0.updatedAt
            )
        }
        // Счета нового ядра event-sourcing (Фаза 1a): cardID у транзакции = account.id.uuidString
        // (см. AccountsCoreCashflowBridge.resolveNewCoreAccount), но кейс `Kind` отдельный —
        // чтобы `id` не сталкивался с легаси-картами. Собственного priority в схеме нет —
        // сортируются по order; «избранное» приходит из `AccountAppearance` (V11).
        let newCoreOptions = newCoreAccounts.map {
            CashflowSelectableAccount(
                kind: .coreAccount(accountID: $0.id.uuidString),
                title: $0.name,
                currency: $0.currency,
                isFavorite: coreFavoriteAccountIDs.contains($0.id),
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
