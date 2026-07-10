import Foundation
import SwiftData
import Testing
@testable import millio

/// 6b Ф5c.1a: маппер экспорта в Google Sheets читает счета нового ядра `Account`
/// (event-sourcing), а не легаси `Card`/`Investment`. Проверяем реплей баланса/позиции
/// и резолвинг счёта транзакции по core-UUID.
@Suite("SheetsDataMapper")
struct SheetsDataMapperTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    @Test @MainActor
    func accountRowReplaysBalanceFromEvents() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = Account(name: "Наличные", kind: .cash, currency: "RUB")
        ctx.insert(account)
        ctx.insert(AccountEvent(account: account, date: Date(timeIntervalSince1970: 1_700_000_000),
                                type: .openingBalance, amount: 1_000))
        ctx.insert(AccountEvent(account: account, date: Date(timeIntervalSince1970: 1_700_100_000),
                                type: .income, amount: 500))
        try ctx.save()

        let data = SheetsDataMapper.buildExportData(transactions: [], accounts: [account], budgets: [])

        #expect(data.accounts.count == 1)
        let row = try #require(data.accounts.first)
        #expect(row.name == "Наличные")
        #expect(row.balance == 1_500)
        #expect(row.type == "cash")
        #expect(row.currency == "RUB")
        #expect(row.millio_id == account.id.uuidString)
        #expect(data.investments.isEmpty)
    }

    @Test @MainActor
    func archivedAccountUsesBalanceAtArchivalDate() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let archivalDate = Date(timeIntervalSince1970: 1_700_050_000)
        let account = Account(name: "Старый счёт", kind: .bankAccount)
        account.archivedAt = archivalDate
        ctx.insert(account)
        ctx.insert(AccountEvent(account: account, date: Date(timeIntervalSince1970: 1_700_000_000),
                                type: .openingBalance, amount: 1_000))
        // Событие ПОСЛЕ архивации — не должно попасть в финальный баланс.
        ctx.insert(AccountEvent(account: account, date: Date(timeIntervalSince1970: 1_700_100_000),
                                type: .income, amount: 999))
        try ctx.save()

        let data = SheetsDataMapper.buildExportData(transactions: [], accounts: [account], budgets: [])

        #expect(data.accounts.isEmpty)
        #expect(data.archivedAccounts.count == 1)
        let row = try #require(data.archivedAccounts.first)
        #expect(row.final_balance == 1_000)
        #expect(row.millio_id == account.id.uuidString)
    }

    @Test @MainActor
    func marketAccountMapsToInvestmentRowWithMovingAverageCostBasis() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = Account(name: "Apple", kind: .marketInvestment, currency: "USD")
        account.marketMeta = MarketMeta(symbol: "AAPL", assetClass: .stock)
        ctx.insert(account)
        let d0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctx.insert(AccountEvent(account: account, date: d0, type: .buy, quantity: 10, unitPrice: 100))
        ctx.insert(AccountEvent(account: account, date: d0.addingTimeInterval(1_000), type: .buy, quantity: 5, unitPrice: 120))
        ctx.insert(AccountEvent(account: account, date: d0.addingTimeInterval(2_000), type: .sell, quantity: 3, unitPrice: 110))
        try ctx.save()

        let data = SheetsDataMapper.buildExportData(transactions: [], accounts: [account], budgets: [])

        // Рыночный счёт уходит в лист Investments, а не Accounts.
        #expect(data.accounts.isEmpty)
        #expect(data.investments.count == 1)
        let row = try #require(data.investments.first)
        #expect(row.name == "Apple")
        #expect(row.ticker == "AAPL")
        #expect(row.buy_currency == "USD")
        // Позиция: buy 10@100 + 5@120 = qty15 / cost1600 (avg 106.6667). sell 3 списывает 3×avg=320.
        #expect(row.quantity == 12)
        let cost = try #require(row.total_cost)
        #expect(abs(cost - 1_280) < 0.001)
        let avg = try #require(row.avg_price)
        #expect(abs(avg - (1_280.0 / 12.0)) < 0.001)
    }

    @Test @MainActor
    func fullySoldMarketAccountReportsZeroPosition() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = Account(name: "BTC", kind: .marketInvestment, currency: "USD")
        account.marketMeta = MarketMeta(symbol: "BTC", assetClass: .crypto)
        ctx.insert(account)
        let d0 = Date(timeIntervalSince1970: 1_700_000_000)
        ctx.insert(AccountEvent(account: account, date: d0, type: .buy, quantity: 2, unitPrice: 50_000))
        ctx.insert(AccountEvent(account: account, date: d0.addingTimeInterval(1_000), type: .sell, quantity: 2, unitPrice: 60_000))
        try ctx.save()

        let data = SheetsDataMapper.buildExportData(transactions: [], accounts: [account], budgets: [])

        let row = try #require(data.investments.first)
        #expect(row.quantity == 0)
        #expect(row.total_cost == 0)
        #expect(row.avg_price == nil)
    }

    @Test @MainActor
    func transactionResolvesAccountByCoreUUID() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let account = Account(name: "Дебетовая", kind: .debitCard, currency: "RUB")
        ctx.insert(account)
        let tx = CashflowTransaction(
            transactionType: .expense,
            amount: -250,
            currency: "RUB",
            transactionDate: Date(timeIntervalSince1970: 1_700_000_000),
            cardID: account.id.uuidString,
            expenseCategory: .groceries,
            affectsCardBalance: true
        )
        ctx.insert(tx)
        try ctx.save()

        let data = SheetsDataMapper.buildExportData(transactions: [tx], accounts: [account], budgets: [])

        let row = try #require(data.transactions.first)
        #expect(row.account == "Дебетовая")
        #expect(row.account_type == "debitCard")
        #expect(row.amount == 250) // всегда положительная
        #expect(row.type == "expense")
    }

    @Test @MainActor
    func transactionWithUnknownCardIDLeavesAccountNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let tx = CashflowTransaction(
            transactionType: .income,
            amount: 1_000,
            currency: "RUB",
            transactionDate: Date(timeIntervalSince1970: 1_700_000_000),
            cardID: "legacy-not-migrated-id",
            incomeCategory: .salary,
            affectsCardBalance: true
        )
        ctx.insert(tx)
        try ctx.save()

        let data = SheetsDataMapper.buildExportData(transactions: [tx], accounts: [], budgets: [])

        let row = try #require(data.transactions.first)
        #expect(row.account == nil)
        #expect(row.account_type == nil)
    }
}
