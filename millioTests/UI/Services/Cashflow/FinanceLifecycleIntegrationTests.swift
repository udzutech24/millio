import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct FinanceLifecycleIntegrationTests {
    @Test("Новая карта сразу доступна в новом расходе без привязки к FinanceAccount")
    func newCardIsImmediatelySelectableForExpense() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 12)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let card = try await harness.createDebitCardOnly(balance: 900)

        let options = CashflowTransactionEditorView.selectableAccounts(
            cards: harness.cashflowViewModel.state.availableCards,
            investments: harness.cashflowViewModel.state.availableInvestments,
            linkedInvestmentIDs: harness.cashflowViewModel.state.linkedInvestmentIDs,
            transactionType: .expense,
            currency: "RUB"
        )

        #expect(options.contains { $0.cardID == card.cardUniqueID })
    }

    @Test("Дебетовая карта проходит полный lifecycle между Finances и Cashflow")
    func debitCardLifecycleStaysConsistentAcrossModules() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let card = try await harness.createLinkedDebitCard(balance: 1_000)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 1_000)
        harness.assertTransactionCount(0)

        try await harness.quickEditCardBalance(cardID: card.cardUniqueID, to: 1_200)
        harness.assertTransactionCount(1)

        let expense = try await harness.persistExpense(cardID: card.cardUniqueID, amount: 200, affectsBalance: true)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 1_000)
        harness.assertTransactionCount(2)

        try await harness.deleteTransaction(expense, recalculate: true)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 1_200)
        harness.assertTransactionCount(1)

        let income = try await harness.persistIncome(cardID: card.cardUniqueID, amount: 150, affectsBalance: true)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 1_350)
        harness.assertTransactionCount(2)

        try await harness.deleteTransaction(income, recalculate: false)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 1_350)
        harness.assertTransactionCount(1)

        try await harness.reloadAll()
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 1_350)
    }

    @Test("History-only расход не меняет баланс и не ломает delete flow")
    func historyOnlyExpenseLifecycleDoesNotAffectBalance() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 9)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let card = try await harness.createLinkedDebitCard(balance: 5_000)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 5_000)

        let expense = try await harness.persistExpense(cardID: card.cardUniqueID, amount: 700, affectsBalance: false)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 5_000)
        harness.assertTransactionCount(1)

        try await harness.deleteTransaction(expense, recalculate: true)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 5_000)
        harness.assertTransactionCount(0)
    }

    @Test("Удаление history-only расхода без пересчета не трогает баланс даже после reload")
    func deletingHistoryOnlyExpenseWithoutRecalculationKeepsBalance() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 11)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let card = try await harness.createLinkedDebitCard(balance: 5_000)
        let expense = try await harness.persistExpense(cardID: card.cardUniqueID, amount: 700, affectsBalance: false)

        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 5_000)
        try await harness.deleteTransaction(expense, recalculate: false)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 5_000)
        try await harness.assertFreshViewModels(
            cardBalances: [card.cardUniqueID: 5_000],
            transactionCount: 0
        )
    }

    @Test("Удаление расхода без пересчета сохраняет уже примененный остаток")
    func deletingAppliedExpenseWithoutRecalculationKeepsAppliedBalance() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 12)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let card = try await harness.createLinkedDebitCard(balance: 5_000)
        let expense = try await harness.persistExpense(cardID: card.cardUniqueID, amount: 700, affectsBalance: true)

        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 4_300)
        try await harness.deleteTransaction(expense, recalculate: false)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 4_300)
        try await harness.assertFreshViewModels(
            cardBalances: [card.cardUniqueID: 4_300],
            transactionCount: 0
        )
    }

    @Test("Кредитная карта: quick edit долга и удаление корректировки откатывают остаток везде")
    func creditCardLifecycleRestoresBalanceAfterDeletingDebtAdjustment() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 17, hour: 10)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let card = try await harness.createLinkedCreditCard(balance: 560_000, creditLimit: 560_000)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 560_000)
        try await harness.assertCreditCardPresentation(cardID: card.cardUniqueID, availableAmount: 560_000, debtAmount: 0)
        harness.assertTransactionCount(0)

        try await harness.quickEditCreditCard(cardID: card.cardUniqueID, creditLimit: 560_000, debt: 100_000)
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 460_000)
        try await harness.assertCreditCardPresentation(cardID: card.cardUniqueID, availableAmount: 460_000, debtAmount: 100_000)
        harness.assertTransactionCount(1)

        let adjustment = try harness.requireTransaction(type: .creditDebtAdjustment, cardID: card.cardUniqueID, amount: -100_000)
        try await harness.deleteTransaction(adjustment, recalculate: true)

        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 560_000)
        try await harness.assertCreditCardPresentation(cardID: card.cardUniqueID, availableAmount: 560_000, debtAmount: 0)
        harness.assertTransactionCount(0)

        try await harness.reloadAll()
        try await harness.assertCardState(cardID: card.cardUniqueID, balance: 560_000)
        try await harness.assertCreditCardPresentation(cardID: card.cardUniqueID, availableAmount: 560_000, debtAmount: 0)
    }

    @Test("Перевод между картами переживает reopen view model и корректно откатывается")
    func transferLifecycleStaysConsistentAfterReopen() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 14)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let sourceCard = try await harness.createLinkedDebitCard(name: "Source", balance: 1_000)
        let destinationCard = try await harness.createLinkedDebitCard(name: "Destination", balance: 300)
        try await harness.assertFreshViewModels(
            cardBalances: [
                sourceCard.cardUniqueID: 1_000,
                destinationCard.cardUniqueID: 300
            ],
            transactionCount: 0
        )

        let transfer = try await harness.persistTransfer(
            from: sourceCard.cardUniqueID,
            to: destinationCard.cardUniqueID,
            amount: 250
        )
        try await harness.assertCardState(cardID: sourceCard.cardUniqueID, balance: 750)
        try await harness.assertCardState(cardID: destinationCard.cardUniqueID, balance: 550)
        try await harness.assertFreshViewModels(
            cardBalances: [
                sourceCard.cardUniqueID: 750,
                destinationCard.cardUniqueID: 550
            ],
            transactionCount: 1
        )

        try await harness.deleteTransaction(transfer, recalculate: true)
        try await harness.assertCardState(cardID: sourceCard.cardUniqueID, balance: 1_000)
        try await harness.assertCardState(cardID: destinationCard.cardUniqueID, balance: 300)
        try await harness.assertFreshViewModels(
            cardBalances: [
                sourceCard.cardUniqueID: 1_000,
                destinationCard.cardUniqueID: 300
            ],
            transactionCount: 0
        )
    }

    @Test("Удаление покупки акции откатывает и деньги, и позицию, а в истории видна одна операция")
    func deletingMarketBuyRevertsSettlementAndPositionTogether() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 16)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let usdCard = try await harness.createLinkedDebitCard(name: "Broker Cash", balance: 5_000, currency: "USD")
        let investment = try await harness.createLinkedMarketInvestment(
            name: "SPY",
            quantity: 17,
            marketPrice: 676.33,
            purchasePrice: 676.33,
            currency: "USD"
        )

        try await harness.executeInvestmentOrder(
            investmentID: investment.investmentUniqueID,
            side: .buy,
            quantity: 1,
            unitPrice: 676.33,
            funding: InvestmentOrderFunding(
                settlementAccountKind: .card(cardID: usdCard.cardUniqueID),
                shouldAffectCardBalance: true
            )
        )

        try await harness.assertCardState(cardID: usdCard.cardUniqueID, balance: 4_323.67)
        try await harness.assertInvestmentState(
            investmentID: investment.investmentUniqueID,
            quantity: 18,
            amount: 12_173.94,
            purchasePrice: 676.33,
            purchaseCost: 12_173.94
        )
        harness.assertTransactionCount(2)

        let visibleHistory = harness.cashflowViewModel.historyTransactions(
            matching: CashflowHistoryQuery(typeFilter: .all)
        )
        #expect(visibleHistory.count == 1)

        guard let groupedTransaction = visibleHistory.first else {
            Issue.record("Expected grouped market order transaction")
            return
        }
        #expect(groupedTransaction.hasAssetChangeSnapshot)
        #expect(groupedTransaction.operationGroupID != nil)

        try await harness.deleteTransaction(groupedTransaction, recalculate: true)

        try await harness.assertCardState(cardID: usdCard.cardUniqueID, balance: 5_000)
        try await harness.assertInvestmentState(
            investmentID: investment.investmentUniqueID,
            quantity: 17,
            amount: 11_497.61,
            purchasePrice: 676.33,
            purchaseCost: 11_497.61
        )
        harness.assertTransactionCount(0)
    }

    @Test("Редактирование сохранённого расхода переносит эффект на новую карту и переживает reopen")
    func editingSavedExpenseReappliesBalanceAcrossCardsAfterReopen() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 19, hour: 11)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let originalCard = try await harness.createLinkedDebitCard(name: "Original", balance: 2_000)
        let replacementCard = try await harness.createLinkedDebitCard(name: "Replacement", balance: 700)

        let expense = try await harness.persistExpense(cardID: originalCard.cardUniqueID, amount: 300, affectsBalance: true)
        try await harness.assertCardState(cardID: originalCard.cardUniqueID, balance: 1_700)
        try await harness.assertCardState(cardID: replacementCard.cardUniqueID, balance: 700)
        try await harness.assertFreshViewModels(
            cardBalances: [
                originalCard.cardUniqueID: 1_700,
                replacementCard.cardUniqueID: 700
            ],
            transactionCount: 1
        )

        let editedExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 450,
            currency: "RUB",
            transactionDate: now,
            cardID: replacementCard.cardUniqueID,
            expenseCategory: .groceries,
            affectsCardBalance: true
        )
        let savedExpense = try await harness.replaceTransaction(expense, with: editedExpense)

        try await harness.assertCardState(cardID: originalCard.cardUniqueID, balance: 2_000)
        try await harness.assertCardState(cardID: replacementCard.cardUniqueID, balance: 250)
        try await harness.assertFreshViewModels(
            cardBalances: [
                originalCard.cardUniqueID: 2_000,
                replacementCard.cardUniqueID: 250
            ],
            transactionCount: 1
        )

        try await harness.deleteTransaction(savedExpense, recalculate: true)
        try await harness.assertCardState(cardID: originalCard.cardUniqueID, balance: 2_000)
        try await harness.assertCardState(cardID: replacementCard.cardUniqueID, balance: 700)
        try await harness.assertFreshViewModels(
            cardBalances: [
                originalCard.cardUniqueID: 2_000,
                replacementCard.cardUniqueID: 700
            ],
            transactionCount: 0
        )
    }

    @Test("Дубликаты карты не создают рассинхрон между Finances и Cashflow")
    func duplicateCardsStayConsistentAcrossModules() async throws {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 11)) ?? Date()
        let harness = try FinanceLifecycleHarness(now: now)

        let sharedID = "DUPLICATE-DEBIT-ID"
        let stale = Card(
            name: "Main",
            cardNumber: "1111",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 1_400
        )
        stale.uniqueID = sharedID
        stale.updatedAt = Date(timeIntervalSince1970: 1)

        let fresh = Card(
            name: "Main",
            cardNumber: "1111",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 900
        )
        fresh.uniqueID = sharedID
        fresh.updatedAt = Date(timeIntervalSince1970: 2)

        harness.modelContext.insert(stale)
        harness.modelContext.insert(fresh)
        let account = FinanceAccount(accountType: .card, accountID: sharedID)
        account.group = harness.group
        harness.modelContext.insert(account)
        try harness.modelContext.save()

        try await harness.reloadAll()
        try await harness.assertCardState(cardID: sharedID, balance: 900)
        try await harness.assertFreshViewModels(cardBalances: [sharedID: 900], transactionCount: 0)
    }
}
