//
//  CashflowPersistenceService.swift
//  millio
//
//  Создан как часть декомпозиции CashflowViewModel (Phase 12).
//  Содержит всю логику создания, обновления и удаления транзакций,
//  а также применения/отката баланса счетов.
//

import Foundation
import SwiftData

// Перенесён из CashflowViewModel (Phase 12) — используется в CashflowPersistenceService и его колбэках.
enum CardBalanceEffectDirection {
    case apply
    case revert
}

@MainActor
final class CashflowPersistenceService {

    // MARK: - Зависимости

    private let modelContext: ModelContext
    private let now: () -> Date
    private let currencyService: CashflowCurrencyService

    // Провайдеры данных
    private let cardProvider: (String) -> Card?
    private let investmentProvider: (String) -> Investment?
    private let transactionsProvider: () -> [CashflowTransaction]
    private let editingTransactionProvider: () -> CashflowTransaction?
    private let normalizedCurrencyCode: (String?) -> String?
    private let ensureSystemCategoriesVisible: ([String?], CashflowCategoryKind, Date) -> Void

    // Callbacks на обновление состояния
    private let onTransactionsMutated: () -> Void
    private let onTransactionsSnapshotMutated: () -> Void
    private let onCardsUpdated: () -> Void
    private let onInvestmentsUpdated: () -> Void
    private let onSetDeleteErrorMessage: (String?) -> Void
    private let onDismissEditor: () -> Void
    private let onEditorIsShowing: () -> Bool
    private let onEditingTransactionMatchesExplicit: (CashflowTransaction) -> Bool
    // Вызывается после успешного сохранения транзакции — fire-and-forget для внешних подписчиков
    private let onTransactionSaved: (() -> Void)?

    // MARK: - Init

    init(
        modelContext: ModelContext,
        now: @escaping () -> Date,
        currencyService: CashflowCurrencyService,
        cardProvider: @escaping (String) -> Card?,
        investmentProvider: @escaping (String) -> Investment?,
        transactionsProvider: @escaping () -> [CashflowTransaction],
        editingTransactionProvider: @escaping () -> CashflowTransaction?,
        normalizedCurrencyCode: @escaping (String?) -> String?,
        ensureSystemCategoriesVisible: @escaping ([String?], CashflowCategoryKind, Date) -> Void,
        onTransactionsMutated: @escaping () -> Void,
        onTransactionsSnapshotMutated: @escaping () -> Void,
        onCardsUpdated: @escaping () -> Void,
        onInvestmentsUpdated: @escaping () -> Void,
        onSetDeleteErrorMessage: @escaping (String?) -> Void,
        onDismissEditor: @escaping () -> Void,
        onEditorIsShowing: @escaping () -> Bool,
        onEditingTransactionMatchesExplicit: @escaping (CashflowTransaction) -> Bool,
        onTransactionSaved: (() -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.now = now
        self.currencyService = currencyService
        self.cardProvider = cardProvider
        self.investmentProvider = investmentProvider
        self.transactionsProvider = transactionsProvider
        self.editingTransactionProvider = editingTransactionProvider
        self.normalizedCurrencyCode = normalizedCurrencyCode
        self.ensureSystemCategoriesVisible = ensureSystemCategoriesVisible
        self.onTransactionsMutated = onTransactionsMutated
        self.onTransactionsSnapshotMutated = onTransactionsSnapshotMutated
        self.onCardsUpdated = onCardsUpdated
        self.onInvestmentsUpdated = onInvestmentsUpdated
        self.onSetDeleteErrorMessage = onSetDeleteErrorMessage
        self.onDismissEditor = onDismissEditor
        self.onEditorIsShowing = onEditorIsShowing
        self.onEditingTransactionMatchesExplicit = onEditingTransactionMatchesExplicit
        self.onTransactionSaved = onTransactionSaved
    }

    // MARK: - Public: Сохранение транзакции

    @discardableResult
    func persistTransaction(
        _ transaction: CashflowTransaction,
        replacing existingTransaction: CashflowTransaction? = nil,
        dismissEditorOnSuccess: Bool = true
    ) async -> Bool {
        await updateTransactionAsync(
            transaction,
            replacing: existingTransaction,
            dismissEditorOnSuccess: dismissEditorOnSuccess
        )
    }

    // MARK: - Public: Удаление транзакции

    func deleteTransactionAsync(_ transaction: CashflowTransaction, recalculate: Bool) async {
        let transactionsToDelete = linkedTransactionsForDelete(containing: transaction)
        let affectedEvents = recalculate
            ? affectedAccountEventsForDelete(transactionsToDelete)
            : []

        if recalculate {
            do {
                try await revertTransactionsForDelete(transactionsToDelete)
            } catch {
                AppLogger.log(.error, category: "Cashflow", "Failed to revert balances on delete: \(error.localizedDescription)")
                onSetDeleteErrorMessage(error.localizedDescription)
                onTransactionsMutated()
                return
            }
        }

        for transactionToDelete in transactionsToDelete {
            modelContext.delete(transactionToDelete)
        }

        do {
            try modelContext.save()
            publishTransactionsUpdated()
            if recalculate {
                onCardsUpdated()
                onInvestmentsUpdated()
                publishAffectedAccountEvents(affectedEvents)
                onTransactionsMutated()
            }
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to delete transaction: \(error.localizedDescription)")
        }
    }

    func deleteTransactionWithoutRecalculation(_ transaction: CashflowTransaction) {
        let preservedBalances = preservedAccountBalances(for: transaction)
        modelContext.delete(transaction)

        do {
            try modelContext.save()
            restorePreservedAccountBalancesIfNeeded(preservedBalances)
            publishTransactionsUpdated()
            onTransactionsSnapshotMutated()
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to delete transaction without recalculation: \(error.localizedDescription)")
        }
    }

    // MARK: - Public: Проверка доступности средств

    func isAmountAvailable(
        amount: Double,
        currency: String,
        fromCardID: String,
        on date: Date,
        replacing existingTransaction: CashflowTransaction? = nil
    ) async throws -> Bool {
        guard let card = cardProvider(fromCardID) else {
            AppLogger.log(.warning, category: "Cashflow", "isAmountAvailable: card not found for fromCardID: \(fromCardID)")
            return false
        }

        let convertedAmount = try await convertAmountForValidation(
            amount: amount,
            from: currency,
            to: card.currency,
            on: date
        )

        let restoredBalance = card.balance + (try await balanceDelta(
            for: existingTransaction,
            onCardID: fromCardID,
            in: card.currency,
            direction: .revert
        ))

        return convertedAmount <= restoredBalance + 0.0001
    }

    // MARK: - Private: Обновление транзакции

    private func updateTransactionAsync(
        _ transaction: CashflowTransaction,
        replacing explicitExistingTransaction: CashflowTransaction? = nil,
        dismissEditorOnSuccess: Bool = true
    ) async -> Bool {
        let existingTransaction = explicitExistingTransaction ?? editingTransactionProvider()
        let affectedEvents = affectedAccountEvents(for: transaction).union(
            existingTransaction.map { affectedAccountEvents(for: $0) } ?? []
        )
        let nowDate = now()
        ensureSystemCategoriesVisible(
            [transaction.incomeCategoryRaw, transaction.expenseCategoryRaw],
            transaction.transactionType == .income ? .income : .expense,
            nowDate
        )
        let exchangeInfo = await currencyService.resolveExchangeInfo(for: transaction)

        if transaction.transactionType == .transfer,
           let targetCurrency = normalizedCurrencyCode(cardProvider(transaction.toCardID ?? "")?.currency),
           normalizedCurrencyCode(transaction.currency) != targetCurrency,
           (exchangeInfo.rate ?? 0) <= 0 {
            AppLogger.log(
                .warning,
                category: "Cashflow",
                "Transfer exchange rate is missing for \(transaction.currency) -> \(String(describing: targetCurrency))"
            )
            return false
        }

        do {
            let isAvailable = try await canPersistTransaction(transaction, replacing: existingTransaction)
            if !isAvailable {
                AppLogger.log(.warning, category: "Cashflow", "Insufficient funds for transaction")
                return false
            }
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Balance validation failed: \(error.localizedDescription)")
            return false
        }

        if let existing = existingTransaction {
            do {
                if persistedBalanceEffectWasApplied(for: existing) {
                    try await applyAccountBalanceEffect(for: existing, direction: .revert)
                    existing.hasAppliedBalanceEffect = false
                }
                if shouldApplyCardBalanceImmediately(for: transaction) {
                    try await applyAccountBalanceEffect(for: transaction, direction: .apply)
                    existing.hasAppliedBalanceEffect = true
                } else {
                    existing.hasAppliedBalanceEffect = false
                }
            } catch {
                AppLogger.log(.error, category: "Cashflow", "Failed to update card balance effect: \(error.localizedDescription)")
                return false
            }

            // Обновляем существующую транзакцию
            existing.transactionTypeRaw = transaction.transactionTypeRaw
            existing.amount = transaction.amount
            existing.currency = transaction.currency
            existing.transactionDate = transaction.transactionDate
            existing.cardID = transaction.cardID
            existing.toCardID = transaction.toCardID
            existing.creditID = transaction.creditID
            existing.investmentID = transaction.investmentID
            existing.operationGroupID = transaction.operationGroupID
            existing.incomeCategoryRaw = transaction.incomeCategoryRaw
            existing.expenseCategoryRaw = transaction.expenseCategoryRaw
            existing.note = transaction.note
            existing.recurrenceRuleRaw = transaction.recurrenceRuleRaw
            existing.recurrenceWeekdaysRaw = transaction.recurrenceWeekdaysRaw
            existing.recurrenceSeriesID = transaction.recurrenceSeriesID
            existing.affectsCardBalance = transaction.affectsCardBalance
            existing.affectsCashflowTotals = transaction.affectsCashflowTotals
            existing.exchangeRate = exchangeInfo.rate
            existing.exchangeRateDate = exchangeInfo.rateDate
            existing.exchangeRateCurrency = exchangeInfo.rateCurrency
            existing.updatedAt = nowDate
        } else {
            // Создаём новую транзакцию
            let newTransaction = CashflowTransaction(
                transactionType: transaction.transactionType,
                amount: transaction.amount,
                currency: transaction.currency,
                transactionDate: transaction.transactionDate,
                cardID: transaction.cardID,
                toCardID: transaction.toCardID,
                creditID: transaction.creditID,
                investmentID: transaction.investmentID,
                incomeCategoryRaw: transaction.incomeCategoryRaw,
                expenseCategoryRaw: transaction.expenseCategoryRaw,
                note: transaction.note,
                operationGroupID: transaction.operationGroupID,
                recurrenceRule: transaction.recurrenceRule,
                recurrenceWeekdays: transaction.recurrenceWeekdays,
                recurrenceSeriesID: transaction.recurrenceSeriesID,
                affectsCardBalance: transaction.affectsCardBalance,
                affectsCashflowTotals: transaction.affectsCashflowTotals
            )
            newTransaction.exchangeRate = exchangeInfo.rate
            newTransaction.exchangeRateDate = exchangeInfo.rateDate
            newTransaction.exchangeRateCurrency = exchangeInfo.rateCurrency
            modelContext.insert(newTransaction)
            do {
                if shouldApplyCardBalanceImmediately(for: newTransaction) {
                    try await applyAccountBalanceEffect(for: newTransaction, direction: .apply)
                    newTransaction.hasAppliedBalanceEffect = true
                }
            } catch {
                AppLogger.log(.error, category: "Cashflow", "Failed to apply card balance effect: \(error.localizedDescription)")
                modelContext.delete(newTransaction)
                return false
            }
        }

        do {
            try modelContext.save()
            publishAffectedAccountEvents(affectedEvents)
            publishTransactionsUpdated()
            onTransactionsMutated()
            if dismissEditorOnSuccess {
                let shouldDismiss: Bool
                if let explicit = explicitExistingTransaction {
                    shouldDismiss = onEditingTransactionMatchesExplicit(explicit)
                } else {
                    shouldDismiss = true
                }
                if shouldDismiss {
                    onDismissEditor()
                }
            }
            onTransactionSaved?()
            return true
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save transaction: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private: Проверка возможности сохранения

    private func canPersistTransaction(
        _ transaction: CashflowTransaction,
        replacing existingTransaction: CashflowTransaction?
    ) async throws -> Bool {
        switch transaction.transactionType {
        case .expense:
            guard shouldApplyCardBalanceImmediately(for: transaction) else {
                return true
            }
            guard transaction.affectsCardBalance,
                  let fromCardID = transaction.cardID else {
                return true
            }
            return try await isAmountAvailable(
                amount: transaction.amount,
                currency: transaction.currency,
                fromCardID: fromCardID,
                on: transaction.transactionDate,
                replacing: existingTransaction
            )
        case .transfer:
            guard shouldApplyCardBalanceImmediately(for: transaction) else {
                return true
            }
            guard let fromCardID = transaction.cardID else {
                return false
            }
            return try await isAmountAvailable(
                amount: transaction.amount,
                currency: transaction.currency,
                fromCardID: fromCardID,
                on: transaction.transactionDate,
                replacing: existingTransaction
            )
        case .income, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return true
        }
    }

    private func shouldApplyCardBalanceImmediately(for transaction: CashflowTransaction) -> Bool {
        switch transaction.transactionType {
        case .income, .expense:
            guard transaction.affectsCardBalance else { return false }
            guard !transaction.isRecurringTemplate else { return false }
            return transaction.transactionDate <= now()
        case .transfer:
            return transaction.transactionDate <= now()
        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return true
        }
    }

    // MARK: - Internal: Применение/откат баланса (вызывается из scheduledService-колбэков VM)

    func applyRecurringTransactionToCardBalance(_ transaction: CashflowTransaction) async {
        guard transaction.affectsCardBalance, let cardID = transaction.cardID else { return }

        let descriptor = FetchDescriptor<Card>()
        let allCards = CardCatalog.deduped((try? modelContext.fetch(descriptor)) ?? [])
        guard let card = allCards.first(where: { $0.archivedAt == nil && $0.cardUniqueID == cardID })
                ?? cardProvider(cardID) else { return }

        let converted = await currencyService.convertAmount(value: transaction.amount, from: transaction.currency, to: card.currency)

        switch transaction.transactionType {
        case .income:
            card.balance += converted
        case .expense:
            card.balance = max(0, card.balance - converted)
        default:
            return
        }
        card.updatedAt = now()
        transaction.hasAppliedBalanceEffect = true
    }

    func applyAccountBalanceEffect(
        for transaction: CashflowTransaction,
        direction: CardBalanceEffectDirection
    ) async throws {
        switch direction {
        case .apply:
            guard shouldApplyCardBalanceImmediately(for: transaction) else { return }
        case .revert:
            guard persistedBalanceEffectWasApplied(for: transaction) else { return }
        }

        let impactedCardIDs = Set([transaction.cardID, transaction.toCardID].compactMap { $0 })
        if !impactedCardIDs.isEmpty {
            let resolvedCards = impactedCardIDs.compactMap { cardID -> (String, Card)? in
                guard let card = cardProvider(cardID) else { return nil }
                return (cardID, card)
            }

            for (cardID, card) in resolvedCards {
                let delta = try await balanceDelta(
                    for: transaction,
                    onCardID: cardID,
                    in: card.currency,
                    direction: direction
                )
                guard abs(delta) > 0.0000001 else { continue }
                let updatedBalance = card.balance + delta
                if updatedBalance < -0.0001 {
                    throw CashflowBalanceUpdateError.insufficientFundsToRevert(
                        accountName: card.name,
                        required: abs(delta),
                        available: card.balance,
                        currency: card.currency
                    )
                }
                card.balance = max(0, updatedBalance)
                card.updatedAt = now()
            }
        }

        if let investmentID = transaction.investmentID,
           let investment = investmentProvider(investmentID) {
            if transaction.transactionType == .balanceAdjustment,
               transaction.hasAssetChangeSnapshot {
                applyInvestmentAssetSnapshot(for: transaction, to: investment, direction: direction)
                investment.updatedAt = now()
                return
            }

            let delta = try await investmentBalanceDelta(
                for: transaction,
                investmentCurrency: investment.currency,
                direction: direction
            )
            guard abs(delta) > 0.0000001 else { return }
            investment.amount = max(0, investment.amount + delta)
            investment.updatedAt = now()
        }
    }

    private func applyInvestmentAssetSnapshot(
        for transaction: CashflowTransaction,
        to investment: Investment,
        direction: CardBalanceEffectDirection
    ) {
        let isApply = direction == .apply
        let quantity = isApply ? transaction.assetQuantityAfter : transaction.assetQuantityBefore
        let unitPrice = isApply ? transaction.assetUnitPriceAfter : transaction.assetUnitPriceBefore
        let totalAmount = isApply ? transaction.assetAmountAfter : transaction.assetAmountBefore
        let purchaseUnitPrice = isApply
            ? transaction.assetPurchaseUnitPriceAfter
            : transaction.assetPurchaseUnitPriceBefore
        let purchaseCost = isApply
            ? transaction.assetPurchaseCostAfter
            : transaction.assetPurchaseCostBefore

        investment.marketQuantity = quantity
        investment.lastKnownUnitPrice = unitPrice
        investment.averagePurchaseUnitPrice = purchaseUnitPrice
        investment.totalPurchaseCost = purchaseCost
        if let totalAmount {
            investment.amount = max(0, totalAmount)
        }
    }

    // MARK: - Private: Дельта баланса

    private func balanceDelta(
        for transaction: CashflowTransaction?,
        onCardID cardID: String,
        in cardCurrency: String,
        direction: CardBalanceEffectDirection
    ) async throws -> Double {
        guard let transaction, shouldAffectCardBalance(transaction) else {
            return 0
        }

        let appliedDelta: Double
        switch transaction.transactionType {
        case .income:
            let amountInCardCurrency = try await convertAmountForValidation(
                amount: transaction.amount,
                from: transaction.currency,
                to: cardCurrency,
                on: transaction.transactionDate
            )
            appliedDelta = transaction.cardID == cardID ? amountInCardCurrency : 0
        case .expense:
            let amountInCardCurrency = try await convertAmountForValidation(
                amount: transaction.amount,
                from: transaction.currency,
                to: cardCurrency,
                on: transaction.transactionDate
            )
            appliedDelta = transaction.cardID == cardID ? -amountInCardCurrency : 0
        case .transfer:
            if transaction.cardID == cardID {
                let amountInCardCurrency = try await convertAmountForValidation(
                    amount: transaction.amount,
                    from: transaction.currency,
                    to: cardCurrency,
                    on: transaction.transactionDate
                )
                appliedDelta = -amountInCardCurrency
            } else if transaction.toCardID == cardID {
                appliedDelta = try await currencyService.transferReceivedAmount(for: transaction, in: cardCurrency)
            } else {
                appliedDelta = 0
            }
        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            let amountInCardCurrency = try await convertAmountForValidation(
                amount: transaction.amount,
                from: transaction.currency,
                to: cardCurrency,
                on: transaction.transactionDate
            )
            appliedDelta = transaction.cardID == cardID ? amountInCardCurrency : 0
        }

        switch direction {
        case .apply:
            return appliedDelta
        case .revert:
            return -appliedDelta
        }
    }

    private func investmentBalanceDelta(
        for transaction: CashflowTransaction?,
        investmentCurrency: String,
        direction: CardBalanceEffectDirection
    ) async throws -> Double {
        guard let transaction, shouldAffectCardBalance(transaction), transaction.investmentID != nil else {
            return 0
        }
        // Grouped market orders keep the settlement leg linked to the traded
        // investment for history reconstruction, but the actual position change
        // is already represented by the balanceAdjustment snapshot transaction.
        guard !isLinkedInvestmentTradeSettlement(transaction) else {
            return 0
        }

        let amountInInvestmentCurrency = try await convertAmountForValidation(
            amount: transaction.amount,
            from: transaction.currency,
            to: investmentCurrency,
            on: transaction.transactionDate
        )

        let appliedDelta: Double
        switch transaction.transactionType {
        case .income, .balanceAdjustment, .cardBalanceAdjustment:
            appliedDelta = amountInInvestmentCurrency
        case .expense:
            appliedDelta = -amountInInvestmentCurrency
        case .transfer, .creditDebtAdjustment:
            appliedDelta = 0
        }

        switch direction {
        case .apply:
            return appliedDelta
        case .revert:
            return -appliedDelta
        }
    }

    private func shouldAffectCardBalance(_ transaction: CashflowTransaction?) -> Bool {
        guard let transaction else { return false }
        switch transaction.transactionType {
        case .income, .expense:
            return transaction.affectsCardBalance
        case .transfer, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return true
        }
    }

    private func convertAmountForValidation(amount: Double, from: String, to: String, on date: Date) async throws -> Double {
        try await currencyService.convertAmountForValidation(amount: amount, from: from, to: to, on: date)
    }

    // MARK: - Private: Состояние применённого эффекта баланса

    private func persistedBalanceEffectWasApplied(for transaction: CashflowTransaction) -> Bool {
        if transaction.hasAppliedBalanceEffect {
            return true
        }
        if isLinkedInvestmentTradeSettlement(transaction) {
            return true
        }
        switch transaction.transactionType {
        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return true
        case .income, .expense, .transfer:
            return shouldApplyCardBalanceImmediately(for: transaction)
        }
    }

    private func isLinkedInvestmentTradeSettlement(_ transaction: CashflowTransaction) -> Bool {
        guard transaction.transactionType == .expense || transaction.transactionType == .income else {
            return false
        }
        guard transaction.investmentID != nil else {
            return false
        }
        guard transaction.shouldAffectCashflowTotals == false else {
            return false
        }
        guard let operationGroupID = transaction.operationGroupID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !operationGroupID.isEmpty else {
            return false
        }

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let storedTransactions = (try? modelContext.fetch(descriptor)) ?? transactionsProvider()
        return storedTransactions.contains { candidate in
            candidate.persistentModelID != transaction.persistentModelID
                && candidate.operationGroupID?.trimmingCharacters(in: .whitespacesAndNewlines) == operationGroupID
                && candidate.hasAssetChangeSnapshot
        }
    }

    // MARK: - Private: Удаление — вспомогательные методы

    private func linkedTransactionsForDelete(containing transaction: CashflowTransaction) -> [CashflowTransaction] {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        let stored = (try? modelContext.fetch(descriptor)) ?? []

        guard let operationGroupID = transaction.operationGroupID,
              !operationGroupID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let storedTransaction = stored.first(where: {
                $0.persistentModelID == transaction.persistentModelID
            }) {
                return [storedTransaction]
            }
            return [transaction]
        }
        let normalizedOperationGroupID = operationGroupID.trimmingCharacters(in: .whitespacesAndNewlines)

        let linked = stored.filter {
            $0.operationGroupID?.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedOperationGroupID
        }
        return linked.isEmpty ? [transaction] : linked
    }

    private func revertTransactionsForDelete(_ transactions: [CashflowTransaction]) async throws {
        for transaction in transactions.sorted(by: deleteRevertPriority) {
            guard persistedBalanceEffectWasApplied(for: transaction) else { continue }
            try await applyAccountBalanceEffect(for: transaction, direction: .revert)
            transaction.hasAppliedBalanceEffect = false
            transaction.updatedAt = now()
        }
    }

    private func affectedAccountEventsForDelete(_ transactions: [CashflowTransaction]) -> Set<CashflowAffectedAccountEvent> {
        var events: Set<CashflowAffectedAccountEvent> = []
        for transaction in transactions where persistedBalanceEffectWasApplied(for: transaction) {
            if transaction.cardID != nil || transaction.toCardID != nil {
                events.insert(.cardsUpdated)
            }
            if transaction.investmentID != nil {
                events.insert(.investmentsUpdated)
            }
        }
        return events
    }

    private func deleteRevertPriority(_ lhs: CashflowTransaction, _ rhs: CashflowTransaction) -> Bool {
        deleteRevertSortKey(for: lhs) < deleteRevertSortKey(for: rhs)
    }

    private func deleteRevertSortKey(for transaction: CashflowTransaction) -> Int {
        if transaction.transactionType == .balanceAdjustment && transaction.hasAssetChangeSnapshot {
            return 1
        }
        return 0
    }

    // MARK: - Private: Affected account events

    private func affectedAccountEvents(for transaction: CashflowTransaction) -> Set<CashflowAffectedAccountEvent> {
        guard shouldApplyCardBalanceImmediately(for: transaction) else { return [] }
        var events = Set<CashflowAffectedAccountEvent>()
        if transaction.cardID != nil || transaction.toCardID != nil {
            events.insert(.cardsUpdated)
        }
        if transaction.investmentID != nil {
            events.insert(.investmentsUpdated)
        }
        return events
    }

    private func publishAffectedAccountEvents(_ events: Set<CashflowAffectedAccountEvent>) {
        for event in events {
            switch event {
            case .cardsUpdated:
                EventBus.shared.publish(FinanceEvent.cardsUpdated)
            case .investmentsUpdated:
                EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            }
        }
    }

    private func publishTransactionsUpdated() {
        EventBus.shared.publish(FinanceEvent.transactionsUpdated)
    }

    // MARK: - Private: Сохранение/восстановление балансов

    private struct PreservedAccountBalances {
        var cardBalances: [String: Double] = [:]
        var investmentBalances: [String: Double] = [:]

        var isEmpty: Bool {
            cardBalances.isEmpty && investmentBalances.isEmpty
        }
    }

    private func preservedAccountBalances(for transaction: CashflowTransaction) -> PreservedAccountBalances {
        var snapshot = PreservedAccountBalances()
        let impactedCardIDs = Set([transaction.cardID, transaction.toCardID].compactMap { $0 })
        for cardID in impactedCardIDs {
            if let card = cardProvider(cardID) {
                snapshot.cardBalances[cardID] = card.balance
            }
        }
        if let investmentID = transaction.investmentID,
           let investment = investmentProvider(investmentID) {
            snapshot.investmentBalances[investmentID] = investment.amount
        }
        return snapshot
    }

    private func restorePreservedAccountBalancesIfNeeded(_ snapshot: PreservedAccountBalances) {
        guard !snapshot.isEmpty else { return }

        var didRestore = false

        for (cardID, balance) in snapshot.cardBalances {
            guard let card = cardProvider(cardID) else { continue }
            guard abs(card.balance - balance) > 0.0000001 else { continue }
            card.balance = balance
            card.updatedAt = now()
            didRestore = true
        }

        for (investmentID, amount) in snapshot.investmentBalances {
            guard let investment = investmentProvider(investmentID) else { continue }
            guard abs(investment.amount - amount) > 0.0000001 else { continue }
            investment.amount = amount
            investment.updatedAt = now()
            didRestore = true
        }

        guard didRestore else { return }

        do {
            try modelContext.save()
            AppLogger.log(
                .warning,
                category: "Cashflow",
                "Restored affected balances after delete without recalculation attempted to mutate them"
            )
        } catch {
            AppLogger.log(
                .error,
                category: "Cashflow",
                "Failed to restore preserved balances after delete without recalculation: \(error.localizedDescription)"
            )
        }
    }
}
