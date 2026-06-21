//
//  FinanceInvestmentOrderServiceTests.swift
//  millioTests
//
//  Регрессионные тесты для бага: после полной продажи акций
//  инвестиционный счёт не удалялся из списка из-за отсутствия
//  выставления archivedAt.
//

import Foundation
import Testing
import SwiftData
@testable import millio

// MARK: - Вспомогательный harness

/// Создаёт FinanceInvestmentOrderService с минимальными замыканиями-заглушками,
/// достаточными для тестирования логики архивации после полной продажи.
@MainActor
private func makeService(
    context: ModelContext,
    investments: [Investment],
    cards: [Card] = []
) -> FinanceInvestmentOrderService {
    let investmentByID: () -> [String: Investment] = {
        Dictionary(uniqueKeysWithValues: investments.map { ($0.investmentUniqueID, $0) })
    }
    return FinanceInvestmentOrderService(
        modelContext: context,
        nowProvider: { Date() },
        investmentByIDProvider: investmentByID,
        cardByIDProvider: { Dictionary(uniqueKeysWithValues: cards.map { ($0.cardUniqueID, $0) }) },
        availableCardsProvider: { cards },
        availableInvestmentsProvider: { investments },
        groupsProvider: { [] },
        resolvedInvestmentCurrency: { $0.currency },
        normalizedConversionCurrency: { $0 },
        normalizedCurrencyCode: { $0 },
        investmentDisplayName: { $0.name },
        onLoadAccounts: {},
        onCalculateTotalAmount: {},
        onScheduleGroupTotalRefresh: { _ in },
        onPublishAccountChangedEvent: { _ in },
        onUpdateTradeCelebration: { _ in }
    )
}

// MARK: - Тесты

@Suite(.serialized)
@MainActor
struct FinanceInvestmentOrderServiceTests {

    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Investment.self,
            CashflowTransaction.self,
            FinanceAccount.self,
            FinanceGroup.self,
            Card.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func makeContext() throws -> ModelContext {
        let ctx = Self.sharedContainer.mainContext
        try ctx.deleteAll(CashflowTransaction.self)
        try ctx.deleteAll(FinanceAccount.self)
        try ctx.deleteAll(Investment.self)
        try ctx.save()
        return ctx
    }

    // MARK: - Сценарий: полная продажа — счёт архивируется

    @Test("После полной продажи всех акций archivedAt выставляется")
    func testFullSellArchivesInvestment() throws {
        let ctx = try makeContext()

        let investment = Investment(
            name: "Apple",
            category: .stocks,
            amount: 10_000,
            currency: "USD"
        )
        investment.marketQuantity = 10
        investment.lastKnownUnitPrice = 100
        investment.averagePurchaseUnitPrice = 100
        investment.totalPurchaseCost = 1000
        ctx.insert(investment)
        try ctx.save()

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        ctx.insert(account)
        try ctx.save()

        let service = makeService(context: ctx, investments: [investment])
        service.executeInvestmentOrder(
            account: account,
            side: .sell,
            quantity: 10,
            unitPrice: 100,
            funding: InvestmentOrderFunding(settlementAccountKind: nil, shouldAffectCardBalance: false)
        )

        // После продажи всех 10 штук позиция нулевая — счёт должен быть заархивирован.
        #expect(investment.marketQuantity == 0)
        #expect(investment.archivedAt != nil, "archivedAt должен быть выставлен после полной продажи")
    }

    // MARK: - Сценарий: частичная продажа — счёт НЕ архивируется

    @Test("После частичной продажи archivedAt НЕ выставляется")
    func testPartialSellDoesNotArchive() throws {
        let ctx = try makeContext()

        let investment = Investment(
            name: "Tesla",
            category: .stocks,
            amount: 5_000,
            currency: "USD"
        )
        investment.marketQuantity = 10
        investment.lastKnownUnitPrice = 250
        investment.averagePurchaseUnitPrice = 250
        investment.totalPurchaseCost = 2500
        ctx.insert(investment)
        try ctx.save()

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        ctx.insert(account)
        try ctx.save()

        let service = makeService(context: ctx, investments: [investment])
        service.executeInvestmentOrder(
            account: account,
            side: .sell,
            quantity: 5,    // продаём только половину
            unitPrice: 250,
            funding: InvestmentOrderFunding(settlementAccountKind: nil, shouldAffectCardBalance: false)
        )

        // Остаток 5 штук — счёт должен оставаться активным.
        #expect((investment.marketQuantity ?? 0) > 0)
        #expect(investment.archivedAt == nil, "archivedAt НЕ должен выставляться при частичной продаже")
    }

    // MARK: - Сценарий: покупка не архивирует

    @Test("Покупка не выставляет archivedAt")
    func testBuyDoesNotArchive() throws {
        let ctx = try makeContext()

        let investment = Investment(
            name: "BTC",
            category: .crypto,
            amount: 0,
            currency: "USD"
        )
        investment.marketQuantity = 0
        ctx.insert(investment)
        try ctx.save()

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        ctx.insert(account)
        try ctx.save()

        let service = makeService(context: ctx, investments: [investment])
        service.executeInvestmentOrder(
            account: account,
            side: .buy,
            quantity: 1,
            unitPrice: 50_000,
            funding: InvestmentOrderFunding(settlementAccountKind: nil, shouldAffectCardBalance: false)
        )

        #expect(investment.archivedAt == nil, "Покупка не должна выставлять archivedAt")
    }

    // MARK: - Юнит-тест модели: applySell обнуляет marketQuantity при полной продаже

    @Test("Investment.applySell обнуляет marketQuantity при продаже всего объёма")
    func testApplySellZerosQuantityOnFullSell() throws {
        let investment = Investment(name: "ETH", category: .crypto, amount: 1000, currency: "USD")
        investment.marketQuantity = 5
        investment.lastKnownUnitPrice = 200
        investment.averagePurchaseUnitPrice = 200
        investment.totalPurchaseCost = 1000

        let result = investment.applySell(quantity: 5, unitPrice: 200)

        #expect(result == true)
        #expect(investment.marketQuantity == 0)
        #expect(investment.totalPurchaseCost == 0)
        #expect(investment.averagePurchaseUnitPrice == nil)
    }
}
