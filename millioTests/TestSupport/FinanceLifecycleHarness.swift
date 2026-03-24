import Foundation
import SwiftData
import Testing
@testable import millio

actor FinanceLifecycleMarketDataClient: MarketDataClientProtocol {
    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol] { [] }
    func latestQuote(symbol: String, forceRefresh: Bool) async throws -> AssetSummary? { nil }
    func fetchQuotes(symbols: [String]) async throws -> [AssetSummary] {
        symbols.map { s in AssetSummary(symbol: s, canonicalSymbol: s, providerSymbol: s, name: nil, exchange: nil, micCode: nil, currency: nil, price: nil, previousClose: nil, change: nil, percentChange: nil, isMarketOpen: nil, resolutionStatus: .notFound, updatedAt: "", isStale: false) }
    }
}

@MainActor
final class FinanceLifecycleHarness {
    static let schema = Schema([
        Card.self,
        Credit.self,
        Investment.self,
        AssetCatalogItem.self,
        AssetProviderMapping.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
        CashflowCustomCategory.self,
        CashflowSystemCategoryOverride.self,
        HistoricalRate.self
    ])

    static var retainedContainers: [ModelContainer] = []

    let modelContext: ModelContext
    let financeViewModel: FinanceViewModel
    let cashflowViewModel: CashflowViewModel
    let cardViewModel: CardViewModel
    let group: FinanceGroup
    let now: Date

    init(now: Date) throws {
        self.now = now

        let defaults = UserDefaults.standard
        defaults.set("RUB", forKey: "primaryCurrencyCode")
        defaults.set(false, forKey: "finance_savings_goal_enabled")
        defaults.set(0, forKey: "finance_savings_goal_amount")
        defaults.removeObject(forKey: "finance_savings_goal_currency")

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)

        self.modelContext = container.mainContext
        self.group = FinanceGroup(name: "Main", colorHex: "#FFFFFF", order: 0)
        modelContext.insert(group)
        try modelContext.save()

        let marketDataClient = FinanceLifecycleMarketDataClient()
        self.financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: nil,
            marketDataClient: marketDataClient,
            now: { now },
            skipInitialLoad: false
        )
        self.cashflowViewModel = CashflowViewModel(modelContext: modelContext, now: { now })
        self.cardViewModel = CardViewModel(modelContext: modelContext)

        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)
        cashflowViewModel.handle(.loadCards)
        cashflowViewModel.handle(.loadTransactions)
    }

    @discardableResult
    func createDebitCardOnly(
        name: String = "Detached debit",
        balance: Double,
        currency: String = "RUB"
    ) async throws -> Card {
        let card = Card(
            name: name,
            cardNumber: "3333",
            bank: .other,
            cardType: .debit,
            currency: currency,
            balance: balance
        )
        cardViewModel.handle(.updateCard(card))

        let created = try requireCard(named: name)
        try await waitUntil {
            self.financeViewModel.state.availableCards.contains(where: { $0.cardUniqueID == created.cardUniqueID })
                && self.cashflowViewModel.state.availableCards.contains(where: { $0.cardUniqueID == created.cardUniqueID })
        }

        return created
    }

    @discardableResult
    func createLinkedDebitCard(
        name: String = "Main debit",
        balance: Double,
        currency: String = "RUB"
    ) async throws -> Card {
        let card = Card(
            name: name,
            cardNumber: "1111",
            bank: .other,
            cardType: .debit,
            currency: currency,
            balance: balance
        )
        cardViewModel.handle(.updateCard(card))

        let created = try requireCard(named: name)
        financeViewModel.handle(.addAccountToGroup(accountType: .card, accountID: created.cardUniqueID, group: group))

        try await waitUntil {
            self.financeAccount(for: created.cardUniqueID) != nil
                && self.financeViewModel.state.availableCards.contains(where: { $0.cardUniqueID == created.cardUniqueID })
                && self.cashflowViewModel.state.availableCards.contains(where: { $0.cardUniqueID == created.cardUniqueID })
        }

        return created
    }

    @discardableResult
    func createLinkedCreditCard(
        name: String = "Main credit",
        balance: Double,
        creditLimit: Double,
        currency: String = "RUB"
    ) async throws -> Card {
        let card = Card(
            name: name,
            cardNumber: "2222",
            bank: .other,
            cardType: .credit,
            currency: currency,
            balance: balance,
            creditLimit: creditLimit
        )
        cardViewModel.handle(.updateCard(card))

        let created = try requireCard(named: name)
        financeViewModel.handle(.addAccountToGroup(accountType: .card, accountID: created.cardUniqueID, group: group))

        try await waitUntil {
            self.financeAccount(for: created.cardUniqueID) != nil
                && self.financeViewModel.state.availableCards.contains(where: { $0.cardUniqueID == created.cardUniqueID })
                && self.cashflowViewModel.state.availableCards.contains(where: { $0.cardUniqueID == created.cardUniqueID })
        }

        return created
    }

    func quickEditCardBalance(cardID: String, to newAmount: Double) async throws {
        let account = try requireFinanceAccount(for: cardID)
        financeViewModel.handle(.updateAccountAmount(account, newAmount))
        try await assertCardState(cardID: cardID, balance: newAmount)
    }

    func quickEditCreditCard(cardID: String, creditLimit: Double, debt: Double) async throws {
        let account = try requireFinanceAccount(for: cardID)
        financeViewModel.handle(.updateCreditCardQuickFields(account: account, creditLimit: creditLimit, debt: debt))
        try await assertCardState(cardID: cardID, balance: max(0, creditLimit - debt))
    }

    @discardableResult
    func createLinkedMarketInvestment(
        name: String,
        quantity: Double,
        marketPrice: Double,
        purchasePrice: Double,
        currency: String = "USD",
        category: InvestmentCategory = .stocks
    ) async throws -> Investment {
        let investment = Investment(
            name: name,
            investmentType: .positive,
            category: category,
            amount: quantity * marketPrice,
            currency: currency
        )
        investment.marketQuantity = quantity
        investment.lastKnownUnitPrice = marketPrice
        investment.averagePurchaseUnitPrice = purchasePrice
        investment.totalPurchaseCost = quantity * purchasePrice
        investment.includeInTotal = true
        modelContext.insert(investment)

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        modelContext.insert(account)
        financeViewModel.handle(.addAccountToGroup(accountType: .investment, accountID: investment.investmentUniqueID, group: group))
        try modelContext.save()

        try await waitUntil {
            self.financeAccount(for: investment.investmentUniqueID, type: .investment) != nil
                && self.financeViewModel.state.availableInvestments.contains(where: { $0.investmentUniqueID == investment.investmentUniqueID })
                && self.cashflowViewModel.state.availableInvestments.contains(where: { $0.investmentUniqueID == investment.investmentUniqueID })
        }

        return investment
    }

    func executeInvestmentOrder(
        investmentID: String,
        side: InvestmentOrderSide,
        quantity: Double,
        unitPrice: Double,
        funding: InvestmentOrderFunding
    ) async throws {
        guard let account = financeAccount(for: investmentID, type: .investment) else {
            Issue.record("Expected finance account for investment \(investmentID)")
            throw HarnessError.missingAccount
        }
        financeViewModel.handle(.executeInvestmentOrder(
            account: account,
            side: side,
            quantity: quantity,
            unitPrice: unitPrice,
            funding: funding
        ))
        try await waitUntil {
            !self.cashflowViewModel.state.transactions.isEmpty
        }
    }

    @discardableResult
    func persistExpense(cardID: String, amount: Double, affectsBalance: Bool = true) async throws -> CashflowTransaction {
        let expense = CashflowTransaction(
            transactionType: .expense,
            amount: amount,
            currency: "RUB",
            transactionDate: now,
            cardID: cardID,
            expenseCategory: .groceries,
            affectsCardBalance: affectsBalance
        )
        let didSave = await cashflowViewModel.persistTransaction(expense)
        #expect(didSave)
        try await waitUntil {
            self.cashflowViewModel.state.transactions.contains {
                $0.cardID == cardID
                    && $0.transactionType == .expense
                    && abs($0.amount - amount) < 0.01
                    && $0.affectsCardBalance == affectsBalance
            }
        }
        return try requireTransaction(type: .expense, cardID: cardID, amount: amount)
    }

    @discardableResult
    func persistIncome(cardID: String, amount: Double, affectsBalance: Bool = true) async throws -> CashflowTransaction {
        let income = CashflowTransaction(
            transactionType: .income,
            amount: amount,
            currency: "RUB",
            transactionDate: now,
            cardID: cardID,
            incomeCategory: .salary,
            affectsCardBalance: affectsBalance
        )
        let didSave = await cashflowViewModel.persistTransaction(income)
        #expect(didSave)
        try await waitUntil {
            self.cashflowViewModel.state.transactions.contains {
                $0.cardID == cardID
                    && $0.transactionType == .income
                    && abs($0.amount - amount) < 0.01
                    && $0.affectsCardBalance == affectsBalance
            }
        }
        return try requireTransaction(type: .income, cardID: cardID, amount: amount)
    }

    @discardableResult
    func persistTransfer(from sourceCardID: String, to destinationCardID: String, amount: Double) async throws -> CashflowTransaction {
        let transfer = CashflowTransaction(
            transactionType: .transfer,
            amount: amount,
            currency: "RUB",
            transactionDate: now,
            cardID: sourceCardID,
            toCardID: destinationCardID,
            expenseCategory: .transfers
        )
        let didSave = await cashflowViewModel.persistTransaction(transfer)
        #expect(didSave)
        try await waitUntil {
            self.cashflowViewModel.state.transactions.contains {
                $0.transactionType == .transfer
                    && $0.cardID == sourceCardID
                    && $0.toCardID == destinationCardID
                    && abs($0.amount - amount) < 0.01
            }
        }
        return try requireTransaction(
            type: .transfer,
            cardID: sourceCardID,
            toCardID: destinationCardID,
            amount: amount
        )
    }

    @discardableResult
    func replaceTransaction(
        _ existing: CashflowTransaction,
        with updated: CashflowTransaction
    ) async throws -> CashflowTransaction {
        let didSave = await cashflowViewModel.persistTransaction(updated, replacing: existing)
        #expect(didSave)
        try await waitUntil {
            self.cashflowViewModel.state.transactions.contains {
                $0.persistentModelID == existing.persistentModelID
                    && $0.transactionType == updated.transactionType
                    && abs($0.amount - updated.amount) < 0.01
                    && $0.cardID == updated.cardID
                    && $0.toCardID == updated.toCardID
                    && $0.affectsCardBalance == updated.affectsCardBalance
            }
        }

        guard let saved = cashflowViewModel.state.transactions.first(where: {
            $0.persistentModelID == existing.persistentModelID
        }) else {
            Issue.record("Expected updated transaction with id \(existing.persistentModelID)")
            throw HarnessError.missingTransaction
        }
        return saved
    }

    func deleteTransaction(_ transaction: CashflowTransaction, recalculate: Bool) async throws {
        let normalizedOperationGroupID = transaction.operationGroupID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cashflowViewModel.handle(.deleteTransaction(transaction, recalculate: recalculate))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            let descriptor = FetchDescriptor<CashflowTransaction>()
            let storedTransactions = (try? self.modelContext.fetch(descriptor)) ?? []

            let originalRemovedFromStore = !storedTransactions.contains {
                $0.persistentModelID == transaction.persistentModelID
            }
            let linkedRemovedFromStore = normalizedOperationGroupID.map { operationGroupID in
                !storedTransactions.contains {
                    $0.operationGroupID?.trimmingCharacters(in: .whitespacesAndNewlines) == operationGroupID
                }
            } ?? true

            let stateTransactions = self.cashflowViewModel.state.transactions
            let originalRemovedFromState = !stateTransactions.contains {
                $0.persistentModelID == transaction.persistentModelID
            }
            let linkedRemovedFromState = normalizedOperationGroupID.map { operationGroupID in
                !stateTransactions.contains {
                    $0.operationGroupID?.trimmingCharacters(in: .whitespacesAndNewlines) == operationGroupID
                }
            } ?? true

            return originalRemovedFromStore
                && linkedRemovedFromStore
                && originalRemovedFromState
                && linkedRemovedFromState
        }

        // Grouped deletes publish several follow-up updates. Force a deterministic
        // refresh here so assertions read converged state instead of racing EventBus.
        try await reloadAll()
    }

    func reloadAll() async throws {
        financeViewModel.handle(.loadAccounts)
        cashflowViewModel.handle(.loadCards)
        cashflowViewModel.handle(.loadTransactions)
        try await waitUntil {
            let cardDescriptor = FetchDescriptor<Card>()
            let investmentDescriptor = FetchDescriptor<Investment>()
            let transactionDescriptor = FetchDescriptor<CashflowTransaction>()

            let storedCards = ((try? self.modelContext.fetch(cardDescriptor)) ?? []).filter { $0.archivedAt == nil }
            let storedInvestments = ((try? self.modelContext.fetch(investmentDescriptor)) ?? []).filter { $0.archivedAt == nil }
            let storedTransactions = (try? self.modelContext.fetch(transactionDescriptor)) ?? []

            return self.financeViewModel.state.availableCards.count == storedCards.count
                && self.financeViewModel.state.availableInvestments.count == storedInvestments.count
                && self.cashflowViewModel.state.availableCards.count == storedCards.count
                && self.cashflowViewModel.state.transactions.count == storedTransactions.count
        }
    }

    func assertCardState(cardID: String, balance: Double) async throws {
        try await waitUntil {
            let financeBalance = self.financeViewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID })?.balance
            let cashflowBalance = self.cashflowViewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID })?.balance
            let modelBalance = self.cardFromStore(cardID: cardID)?.balance
            let snapshotBalance = self.cashflowViewModel.cardBalanceSnapshot(for: cardID)?.availableAmount

            return Self.approximatelyEqual(financeBalance, balance)
                && Self.approximatelyEqual(cashflowBalance, balance)
                && Self.approximatelyEqual(modelBalance, balance)
                && Self.approximatelyEqual(snapshotBalance, balance)
        }

        #expect(Self.approximatelyEqual(cardFromStore(cardID: cardID)?.balance, balance))
        #expect(Self.approximatelyEqual(financeViewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID })?.balance, balance))
        #expect(Self.approximatelyEqual(cashflowViewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID })?.balance, balance))
        #expect(Self.approximatelyEqual(cashflowViewModel.cardBalanceSnapshot(for: cardID)?.availableAmount, balance))
    }

    func assertFreshViewModels(
        cardBalances: [String: Double],
        transactionCount expectedTransactionCount: Int
    ) async throws {
        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: nil,
            marketDataClient: FinanceLifecycleMarketDataClient(),
            now: { self.now },
            skipInitialLoad: false
        )
        let cashflowViewModel = CashflowViewModel(modelContext: modelContext, now: { self.now })

        try await waitUntil {
            cashflowViewModel.state.transactions.count == expectedTransactionCount
                && cardBalances.allSatisfy { cardID, balance in
                    Self.approximatelyEqual(
                        financeViewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID })?.balance,
                        balance
                    ) && Self.approximatelyEqual(
                        cashflowViewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID })?.balance,
                        balance
                    ) && Self.approximatelyEqual(
                        cashflowViewModel.cardBalanceSnapshot(for: cardID)?.availableAmount,
                        balance
                    )
                }
        }

        #expect(cashflowViewModel.state.transactions.count == expectedTransactionCount)
        for (cardID, balance) in cardBalances {
            #expect(
                Self.approximatelyEqual(
                    financeViewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID })?.balance,
                    balance
                )
            )
            #expect(
                Self.approximatelyEqual(
                    cashflowViewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID })?.balance,
                    balance
                )
            )
            #expect(
                Self.approximatelyEqual(
                    cashflowViewModel.cardBalanceSnapshot(for: cardID)?.availableAmount,
                    balance
                )
            )
        }
    }

    func assertCreditCardPresentation(
        cardID: String,
        availableAmount: Double,
        debtAmount: Double
    ) async throws {
        try await waitUntil {
            guard let financeAccount = self.financeAccount(for: cardID) else {
                return false
            }
            let financeMainAmount = self.financeViewModel.getAccountInfo(account: financeAccount)?.amount
            let financeRemaining = self.financeViewModel.getCreditCardLimitRemaining(account: financeAccount)?.amount
            let financeDebt = self.financeViewModel.getCreditCardDebt(account: financeAccount)?.amount ?? 0
            let cashflowAvailable = self.cashflowViewModel.cardBalanceSnapshot(for: cardID)?.availableAmount
            let cashflowDebt = self.cashflowViewModel.cardBalanceSnapshot(for: cardID)?.debtAmount ?? 0

            return Self.approximatelyEqual(financeMainAmount, debtAmount)
                && Self.approximatelyEqual(financeRemaining, availableAmount)
                && Self.approximatelyEqual(financeDebt, debtAmount)
                && Self.approximatelyEqual(cashflowAvailable, availableAmount)
                && Self.approximatelyEqual(cashflowDebt, debtAmount)
        }

        let financeAccount = try requireFinanceAccount(for: cardID)
        #expect(Self.approximatelyEqual(financeViewModel.getAccountInfo(account: financeAccount)?.amount, debtAmount))
        #expect(Self.approximatelyEqual(financeViewModel.getCreditCardLimitRemaining(account: financeAccount)?.amount, availableAmount))
        #expect(Self.approximatelyEqual(financeViewModel.getCreditCardDebt(account: financeAccount)?.amount ?? 0, debtAmount))
        #expect(Self.approximatelyEqual(cashflowViewModel.cardBalanceSnapshot(for: cardID)?.availableAmount, availableAmount))
        #expect(Self.approximatelyEqual(cashflowViewModel.cardBalanceSnapshot(for: cardID)?.debtAmount ?? 0, debtAmount))
    }

    func assertInvestmentState(
        investmentID: String,
        quantity: Double,
        amount: Double,
        purchasePrice: Double?,
        purchaseCost: Double?
    ) async throws {
        try await waitUntil {
            guard let investment = self.investmentFromStore(investmentID: investmentID) else {
                return false
            }
            return Self.approximatelyEqual(investment.marketQuantity, quantity, epsilon: 0.000001)
                && Self.approximatelyEqual(investment.amount, amount)
                && Self.approximatelyEqual(investment.averagePurchaseUnitPrice, purchasePrice, epsilon: 0.000001)
                && Self.approximatelyEqual(investment.totalPurchaseCost, purchaseCost, epsilon: 0.000001)
        }

        let investment = try requireInvestment(investmentID: investmentID)
        #expect(Self.approximatelyEqual(investment.marketQuantity, quantity, epsilon: 0.000001))
        #expect(Self.approximatelyEqual(investment.amount, amount))
        #expect(Self.approximatelyEqual(investment.averagePurchaseUnitPrice, purchasePrice, epsilon: 0.000001))
        #expect(Self.approximatelyEqual(investment.totalPurchaseCost, purchaseCost, epsilon: 0.000001))
    }

    func assertTransactionCount(_ expected: Int) {
        #expect(cashflowViewModel.state.transactions.count == expected)
    }

    func requireFinanceAccount(for cardID: String) throws -> FinanceAccount {
        guard let account = financeAccount(for: cardID) else {
            Issue.record("Expected finance account for card \(cardID)")
            throw HarnessError.missingAccount
        }
        return account
    }

    func requireInvestment(investmentID: String) throws -> Investment {
        guard let investment = investmentFromStore(investmentID: investmentID) else {
            Issue.record("Expected investment \(investmentID)")
            throw HarnessError.missingAccount
        }
        return investment
    }

    func requireTransaction(
        type: CashflowTransactionType,
        cardID: String,
        toCardID: String? = nil,
        amount: Double
    ) throws -> CashflowTransaction {
        guard let transaction = cashflowViewModel.state.transactions.first(where: {
            $0.transactionType == type
                && $0.cardID == cardID
                && $0.toCardID == toCardID
                && abs($0.amount - amount) < 0.01
        }) else {
            Issue.record("Expected \(type.rawValue) transaction for card \(cardID)")
            throw HarnessError.missingTransaction
        }
        return transaction
    }

    func requireCard(named name: String) throws -> Card {
        let descriptor = FetchDescriptor<Card>()
        let cards = (try? modelContext.fetch(descriptor)) ?? []
        guard let card = cards.first(where: { $0.name == name }) else {
            Issue.record("Expected card named \(name)")
            throw HarnessError.missingCard
        }
        return card
    }

    private func financeAccount(for cardID: String) -> FinanceAccount? {
        financeAccount(for: cardID, type: .card)
    }

    private func financeAccount(for accountID: String, type: FinanceAccountType) -> FinanceAccount? {
        financeViewModel.state.groups
            .flatMap { $0.accounts ?? [] }
            .first { $0.accountType == type && $0.accountID == accountID }
    }

    private func cardFromStore(cardID: String) -> Card? {
        let descriptor = FetchDescriptor<Card>()
        let cards = (try? modelContext.fetch(descriptor)) ?? []
        return cards.first(where: { $0.cardUniqueID == cardID })
    }

    private func investmentFromStore(investmentID: String) -> Investment? {
        let descriptor = FetchDescriptor<Investment>()
        let investments = (try? modelContext.fetch(descriptor)) ?? []
        return investments.first(where: { $0.investmentUniqueID == investmentID })
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        intervalNanoseconds: UInt64 = 50_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        #expect(Bool(false), "Condition was not met before timeout")
    }

    private static func approximatelyEqual(_ lhs: Double?, _ rhs: Double?, epsilon: Double = 0.01) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return abs(lhs - rhs) < epsilon
        default:
            return false
        }
    }

    private static func approximatelyEqual(_ lhs: Double?, _ rhs: Double, epsilon: Double = 0.01) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) < epsilon
    }

    enum HarnessError: Error {
        case missingCard
        case missingAccount
        case missingTransaction
    }
}
