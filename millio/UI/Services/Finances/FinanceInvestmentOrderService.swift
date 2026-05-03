//
//  FinanceInvestmentOrderService.swift
//  millio
//
//  Создан как часть декомпозиции FinanceViewModel (Phase 10).
//  Содержит логику рыночных ордеров (buy/sell) и обновления
//  рыночных деталей инвестиционного счёта.
//

import Foundation
import SwiftData

@MainActor
final class FinanceInvestmentOrderService {

    // MARK: - Private: Зависимости (через замыкания)

    private let modelContext: ModelContext
    private let nowProvider: () -> Date

    // Провайдеры состояния из VM
    private let investmentByIDProvider: () -> [String: Investment]
    private let cardByIDProvider: () -> [String: Card]
    private let availableCardsProvider: () -> [Card]
    private let availableInvestmentsProvider: () -> [Investment]
    private let groupsProvider: () -> [FinanceGroup]

    // Делегирование вычислений в другие сервисы / VM
    private let resolvedInvestmentCurrency: (Investment) -> String
    private let normalizedConversionCurrency: (String) -> String
    private let normalizedCurrencyCode: (String) -> String
    private let investmentDisplayName: (Investment) -> String

    // Callbacks на мутации в VM
    private let onLoadAccounts: () -> Void
    private let onCalculateTotalAmount: () -> Void
    private let onScheduleGroupTotalRefresh: (String) -> Void
    private let onPublishAccountChangedEvent: (FinanceAccountType) -> Void
    private let onUpdateTradeCelebration: (FinanceTradeCelebration) -> Void

    // MARK: - Init

    init(
        modelContext: ModelContext,
        nowProvider: @escaping () -> Date,
        investmentByIDProvider: @escaping () -> [String: Investment],
        cardByIDProvider: @escaping () -> [String: Card],
        availableCardsProvider: @escaping () -> [Card],
        availableInvestmentsProvider: @escaping () -> [Investment],
        groupsProvider: @escaping () -> [FinanceGroup],
        resolvedInvestmentCurrency: @escaping (Investment) -> String,
        normalizedConversionCurrency: @escaping (String) -> String,
        normalizedCurrencyCode: @escaping (String) -> String,
        investmentDisplayName: @escaping (Investment) -> String,
        onLoadAccounts: @escaping () -> Void,
        onCalculateTotalAmount: @escaping () -> Void,
        onScheduleGroupTotalRefresh: @escaping (String) -> Void,
        onPublishAccountChangedEvent: @escaping (FinanceAccountType) -> Void,
        onUpdateTradeCelebration: @escaping (FinanceTradeCelebration) -> Void
    ) {
        self.modelContext = modelContext
        self.nowProvider = nowProvider
        self.investmentByIDProvider = investmentByIDProvider
        self.cardByIDProvider = cardByIDProvider
        self.availableCardsProvider = availableCardsProvider
        self.availableInvestmentsProvider = availableInvestmentsProvider
        self.groupsProvider = groupsProvider
        self.resolvedInvestmentCurrency = resolvedInvestmentCurrency
        self.normalizedConversionCurrency = normalizedConversionCurrency
        self.normalizedCurrencyCode = normalizedCurrencyCode
        self.investmentDisplayName = investmentDisplayName
        self.onLoadAccounts = onLoadAccounts
        self.onCalculateTotalAmount = onCalculateTotalAmount
        self.onScheduleGroupTotalRefresh = onScheduleGroupTotalRefresh
        self.onPublishAccountChangedEvent = onPublishAccountChangedEvent
        self.onUpdateTradeCelebration = onUpdateTradeCelebration
    }

    // MARK: - Public: Ордера

    func executeInvestmentOrder(
        account: FinanceAccount,
        side: InvestmentOrderSide,
        quantity: Double,
        unitPrice: Double,
        funding: InvestmentOrderFunding
    ) {
        guard quantity > 0, unitPrice >= 0 else {
            return
        }
        guard account.accountType == .investment,
              let investment = investmentByIDProvider()[account.accountID],
              investment.isMarketPriced else {
            return
        }

        let investmentCurrency = resolvedInvestmentCurrency(investment)
        let totalAmount = quantity * unitPrice
        let normalizedFunding = normalizedInvestmentOrderFunding(
            funding,
            cards: availableCardsProvider(),
            investments: availableInvestmentsProvider(),
            investmentID: investment.investmentUniqueID,
            investmentCurrency: investmentCurrency
        )
        guard !normalizedFunding.shouldAffectCardBalance || normalizedFunding.settlementAccountKind != nil else {
            return
        }
        let settlementAccountForOrder = settlementAccount(
            for: normalizedFunding,
            investmentCurrency: investmentCurrency
        )
        if normalizedFunding.shouldAffectCardBalance, settlementAccountForOrder == nil {
            return
        }
        if let settlementAccountForOrder,
           side == .buy,
           settlementAccountForOrder.availableAmount + 0.0000001 < totalAmount {
            return
        }

        let oldAmount = investment.amount
        let transactionDate = nowProvider()
        if !investment.hasInitialAmount {
            investment.initialAmount = investment.amount
            investment.hasInitialAmount = true
        }

        let snapshotBefore = marketAssetSnapshot(for: investment)
        let settlementAmountBefore = settlementAccountForOrder?.availableAmount
        let didApply: Bool
        switch side {
        case .buy:
            didApply = investment.applyBuy(quantity: quantity, unitPrice: unitPrice)
        case .sell:
            didApply = investment.applySell(quantity: quantity, unitPrice: unitPrice)
        }
        guard didApply else {
            return
        }
        investment.updatedAt = transactionDate

        if let settlementAccountForOrder {
            switch settlementAccountForOrder {
            case .card(let card):
                if !card.hasInitialBalance {
                    card.initialBalance = card.balance
                    card.hasInitialBalance = true
                }
                switch side {
                case .buy:
                    card.balance = max(0, card.balance - totalAmount)
                case .sell:
                    card.balance += totalAmount
                }
                card.updatedAt = transactionDate
            case .investment(let settlementInvestment):
                if !settlementInvestment.hasInitialAmount {
                    settlementInvestment.initialAmount = settlementInvestment.amount
                    settlementInvestment.hasInitialAmount = true
                }
                switch side {
                case .buy:
                    settlementInvestment.amount = max(0, settlementInvestment.amount - totalAmount)
                case .sell:
                    settlementInvestment.amount += totalAmount
                }
                settlementInvestment.updatedAt = transactionDate
            }
        }

        do {
            var didCreateTransaction = false
            var changedAccountTypes: Set<FinanceAccountType> = [.investment]
            let difference = investment.amount - oldAmount
            let operationGroupID = UUID().uuidString
            if abs(difference) > 0.01 {
                let note = side == .buy
                    ? String(localized: "finances.transaction.note.investment_buy")
                    : String(localized: "finances.transaction.note.investment_sell")
                let transaction = CashflowTransaction(
                    transactionType: .balanceAdjustment,
                    amount: difference,
                    currency: investment.currency,
                    transactionDate: transactionDate,
                    investmentID: investment.investmentUniqueID,
                    note: note,
                    operationGroupID: operationGroupID
                )
                transaction.applyAssetChangeSnapshot(
                    before: snapshotBefore,
                    after: marketAssetSnapshot(for: investment)
                )
                stampFrozenRate(on: transaction, targetCurrency: investmentCurrency)
                transaction.hasAppliedBalanceEffect = true
                modelContext.insert(transaction)
                didCreateTransaction = true
            }

            if let settlementAccountForOrder {
                let note = side == .buy
                    ? String(localized: "finances.transaction.note.investment_buy")
                    : String(localized: "finances.transaction.note.investment_sell")
                let settlementCardID: String?
                switch settlementAccountForOrder {
                case .card(let card):
                    settlementCardID = card.cardUniqueID
                case .investment:
                    settlementCardID = nil
                }
                let settlementTransaction = CashflowTransaction(
                    transactionType: side == .buy ? .expense : .income,
                    amount: totalAmount,
                    currency: investmentCurrency,
                    transactionDate: transactionDate,
                    cardID: settlementCardID,
                    // Keep the order leg attached to the traded investment so
                    // audit/history queries can reconstruct the full operation.
                    investmentID: investment.investmentUniqueID,
                    incomeCategory: side == .sell ? .investment : nil,
                    expenseCategory: side == .buy ? .other : nil,
                    note: note,
                    operationGroupID: operationGroupID,
                    affectsCashflowTotals: false
                )
                stampFrozenRate(on: settlementTransaction, targetCurrency: settlementAccountForOrder.currency)
                settlementTransaction.hasAppliedBalanceEffect = true
                modelContext.insert(settlementTransaction)
                didCreateTransaction = true
                changedAccountTypes.insert(settlementAccountForOrder.accountType)
            }

            try modelContext.save()
            onLoadAccounts()
            onCalculateTotalAmount()
            onUpdateTradeCelebration(FinanceTradeCelebration(
                side: side,
                investmentName: investmentDisplayName(investment),
                investmentCategory: investment.category,
                totalAmount: totalAmount,
                currency: investmentCurrency
            ))

            var affectedGroupIDs: Set<String> = []
            for group in groupsProvider() {
                guard let groupAccounts = group.accounts else { continue }
                if groupAccounts.contains(where: { $0.accountType == .investment && $0.accountID == account.accountID }) {
                    affectedGroupIDs.insert(group.groupUniqueID)
                }
                if let settlementAccountForOrder,
                   groupAccounts.contains(where: {
                       $0.accountType == settlementAccountForOrder.accountType
                           && $0.accountID == settlementAccountForOrder.accountID
                   }) {
                    affectedGroupIDs.insert(group.groupUniqueID)
                }
            }
            for groupID in affectedGroupIDs {
                onScheduleGroupTotalRefresh(groupID)
            }

            for accountType in changedAccountTypes {
                onPublishAccountChangedEvent(accountType)
            }

            if didCreateTransaction {
                EventBus.shared.publish(FinanceEvent.transactionsUpdated)
            }
        } catch {
            if let settlementAccountForOrder, let settlementAmountBefore {
                switch settlementAccountForOrder {
                case .card(let card):
                    card.balance = settlementAmountBefore
                case .investment(let settlementInvestment):
                    settlementInvestment.amount = settlementAmountBefore
                }
            }
            AppLogger.log(.error, category: "Finance", "Failed to execute market order: \(error.localizedDescription)")
        }
    }

    func updateMarketInvestmentDetails(
        account: FinanceAccount,
        quantity: Double,
        unitPrice: Double,
        purchaseUnitPrice: Double?
    ) {
        guard account.accountType == .investment,
              let investment = investmentByIDProvider()[account.accountID],
              investment.isMarketPriced,
              quantity > 0,
              unitPrice > 0 else {
            return
        }

        let snapshotBefore = marketAssetSnapshot(for: investment)
        let oldAmount = investment.amount
        if !investment.hasInitialAmount {
            investment.initialAmount = investment.amount
            investment.hasInitialAmount = true
        }

        investment.marketQuantity = quantity
        investment.lastKnownUnitPrice = unitPrice
        investment.lastKnownPriceUpdatedAt = Date()

        if let purchaseUnitPrice, purchaseUnitPrice > 0 {
            investment.averagePurchaseUnitPrice = purchaseUnitPrice
            investment.totalPurchaseCost = purchaseUnitPrice * quantity
        } else {
            investment.averagePurchaseUnitPrice = nil
            investment.totalPurchaseCost = nil
        }

        investment.recalculateAmountFromPosition()
        investment.updatedAt = Date()

        do {
            var didCreateTransaction = false
            let difference = investment.amount - oldAmount
            if abs(difference) > 0.01 {
                let transaction = CashflowTransaction(
                    transactionType: .balanceAdjustment,
                    amount: difference,
                    currency: investment.currency,
                    transactionDate: Date(),
                    investmentID: investment.investmentUniqueID,
                    note: String(localized: "finances.transaction.note.market_position_edit")
                )
                transaction.applyAssetChangeSnapshot(
                    before: snapshotBefore,
                    after: marketAssetSnapshot(for: investment)
                )
                stampFrozenRate(on: transaction, targetCurrency: resolvedInvestmentCurrency(investment))
                transaction.hasAppliedBalanceEffect = true
                modelContext.insert(transaction)
                didCreateTransaction = true
            }

            try modelContext.save()
            onLoadAccounts()
            onCalculateTotalAmount()

            if let accountGroupID = groupsProvider().first(where: { group in
                group.accounts?.contains(where: { $0.id == account.id }) == true
            })?.groupUniqueID {
                onScheduleGroupTotalRefresh(accountGroupID)
            }

            if didCreateTransaction {
                EventBus.shared.publish(FinanceEvent.transactionsUpdated)
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to update market investment details: \(error.localizedDescription)")
        }
    }

    // MARK: - Public: Static helpers

    static func eligibleSettlementCards(
        from cards: [Card],
        investmentCurrency: String
    ) -> [Card] {
        let normalizedInvestmentCurrency = investmentCurrency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        return cards.filter { card in
            card.archivedAt == nil
                && card.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedInvestmentCurrency
        }
    }

    static func eligibleSettlementAccounts(
        cards: [Card],
        investments: [Investment],
        investmentCurrency: String,
        excludingInvestmentID: String? = nil
    ) -> [CashflowSelectableAccount] {
        let cardOptions = eligibleSettlementCards(
            from: cards,
            investmentCurrency: investmentCurrency
        ).map {
            CashflowSelectableAccount(
                kind: .card(cardID: $0.cardUniqueID),
                title: $0.name,
                currency: $0.currency,
                isFavorite: $0.isFavorite,
                prioritySortOrder: $0.priority.sortOrder,
                updatedAt: $0.updatedAt
            )
        }

        let normalizedCurrency = investmentCurrency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let investmentOptions = investments
            .filter { investment in
                investment.archivedAt == nil
                    && investment.isCashflowAccount
                    && investment.investmentUniqueID != excludingInvestmentID
                    && investment.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCurrency
            }
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

        return (cardOptions + investmentOptions).sorted { lhs, rhs in
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

    // MARK: - Private: Внутреннее состояние расчётного счёта

    private enum InvestmentSettlementAccount {
        case card(Card)
        case investment(Investment)

        var accountType: FinanceAccountType {
            switch self {
            case .card:
                return .card
            case .investment:
                return .investment
            }
        }

        var accountID: String {
            switch self {
            case .card(let card):
                return card.cardUniqueID
            case .investment(let investment):
                return investment.investmentUniqueID
            }
        }

        var currency: String {
            switch self {
            case .card(let card):
                return card.currency
            case .investment(let investment):
                return investment.currency
            }
        }

        var availableAmount: Double {
            switch self {
            case .card(let card):
                return card.balance
            case .investment(let investment):
                return investment.amount
            }
        }
    }

    // MARK: - Private: Хелперы

    private func normalizedInvestmentOrderFunding(
        _ funding: InvestmentOrderFunding,
        cards: [Card],
        investments: [Investment],
        investmentID: String,
        investmentCurrency: String
    ) -> InvestmentOrderFunding {
        guard funding.shouldAffectCardBalance else {
            return .ignored
        }

        let eligibleAccounts = Self.eligibleSettlementAccounts(
            cards: cards,
            investments: investments,
            investmentCurrency: investmentCurrency,
            excludingInvestmentID: investmentID
        )
        guard !eligibleAccounts.isEmpty else {
            return .ignored
        }

        if let settlementAccountKind = funding.settlementAccountKind,
           eligibleAccounts.contains(where: { $0.kind == settlementAccountKind }) {
            return InvestmentOrderFunding(
                settlementAccountKind: settlementAccountKind,
                shouldAffectCardBalance: true
            )
        }

        let preferredAccount = eligibleAccounts.first
        return InvestmentOrderFunding(
            settlementAccountKind: preferredAccount?.kind,
            shouldAffectCardBalance: preferredAccount != nil
        )
    }

    private func settlementAccount(
        for funding: InvestmentOrderFunding,
        investmentCurrency: String
    ) -> InvestmentSettlementAccount? {
        guard funding.shouldAffectCardBalance,
              let settlementAccountKind = funding.settlementAccountKind else {
            return nil
        }

        let normalizedInvestmentCurrency = normalizedCurrencyCode(investmentCurrency)
        switch settlementAccountKind {
        case .card(let cardID):
            guard let card = cardByIDProvider()[cardID],
                  normalizedCurrencyCode(card.currency) == normalizedInvestmentCurrency else {
                return nil
            }
            return .card(card)
        case .investment(let investmentID):
            guard let investment = investmentByIDProvider()[investmentID],
                  investment.isCashflowAccount,
                  normalizedCurrencyCode(investment.currency) == normalizedInvestmentCurrency else {
                return nil
            }
            return .investment(investment)
        }
    }

    private func stampFrozenRate(on transaction: CashflowTransaction, targetCurrency: String) {
        let normalizedSource = normalizedConversionCurrency(transaction.currency)
        let normalizedTarget = normalizedConversionCurrency(targetCurrency)
        transaction.currency = normalizedSource
        transaction.exchangeRateCurrency = normalizedTarget
        transaction.exchangeRateDate = Calendar.current.startOfDay(for: transaction.transactionDate)
        if normalizedSource == normalizedTarget {
            transaction.exchangeRate = 1.0
        }
    }

    private func marketAssetSnapshot(for investment: Investment) -> CashflowAssetChangeSnapshot {
        CashflowAssetChangeSnapshot(
            quantity: investment.marketQuantity,
            unitPrice: investment.lastKnownUnitPrice,
            purchaseUnitPrice: investment.averagePurchaseUnitPrice,
            purchaseCost: investment.totalPurchaseCost,
            totalAmount: investment.amount
        )
    }
}
