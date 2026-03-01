import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct InvestmentMarketModelTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([Investment.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func makeContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(Investment.self)
        try context.save()
        return context
    }

    @Test("positionTotal и recalculateAmountFromPosition работают для рыночного актива")
    func testPositionTotalAndRecalculation() throws {
        let investment = Investment(
            name: "AAPL",
            investmentType: .positive,
            category: .stocks,
            amount: 0,
            currency: "USD",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        investment.marketQuantity = 4
        investment.lastKnownUnitPrice = 250

        #expect(investment.positionTotal == 1000)

        investment.recalculateAmountFromPosition()
        #expect(investment.amount == 1000)
    }

    @Test("InvestmentImporter импортирует старый backup без market-полей")
    func testLegacyImportWithoutMarketFields() throws {
        let context = try makeContext()

        let payload: [String: Any] = [
            "type": "Investment",
            "name": "Legacy Asset",
            "investmentTypeRaw": "positive",
            "categoryRaw": "other",
            "amount": 12345.0,
            "currency": "RUB",
            "includeInTotal": true,
            "priorityRaw": "normal",
            "isFavorite": false,
            "createdAt": Date().timeIntervalSince1970,
            "updatedAt": Date().timeIntervalSince1970,
            "investmentUniqueID": "legacy-asset-id"
        ]

        try InvestmentImporter.import(from: payload, context: context)
        try context.save()

        let descriptor = FetchDescriptor<Investment>()
        let items = try context.fetch(descriptor)

        #expect(items.count == 1)

        let imported = try #require(items.first)
        #expect(imported.name == "Legacy Asset")
        #expect(imported.marketSymbol == nil)
        #expect(imported.marketQuantity == nil)
        #expect(imported.lastKnownUnitPrice == nil)
        #expect(imported.marketProviderRaw == nil)
    }

    @Test("applyBuy/applySell корректно ведут среднюю цену покупки")
    func testBuySellAveragePurchasePrice() throws {
        let investment = Investment(
            name: "AAPL",
            investmentType: .positive,
            category: .stocks,
            amount: 0,
            currency: "USD"
        )

        #expect(investment.applyBuy(quantity: 10, unitPrice: 100))
        #expect(investment.marketQuantity == 10)
        #expect(abs((investment.averagePurchaseUnitPrice ?? 0) - 100) < 0.0001)
        #expect(abs((investment.totalPurchaseCost ?? 0) - 1000) < 0.0001)

        #expect(investment.applyBuy(quantity: 10, unitPrice: 200))
        #expect(investment.marketQuantity == 20)
        #expect(abs((investment.averagePurchaseUnitPrice ?? 0) - 150) < 0.0001)
        #expect(abs((investment.totalPurchaseCost ?? 0) - 3000) < 0.0001)

        #expect(investment.applySell(quantity: 5, unitPrice: 220))
        #expect(abs((investment.marketQuantity ?? 0) - 15) < 0.0001)
        #expect(abs((investment.averagePurchaseUnitPrice ?? 0) - 150) < 0.0001)
        #expect(abs((investment.totalPurchaseCost ?? 0) - 2250) < 0.0001)

        #expect(investment.applySell(quantity: 20, unitPrice: 220) == false)
    }

    @Test("positionGrowthAbsolute/positionGrowthPercent возвращают корректный прирост")
    func testPositionGrowthMetrics() {
        let investment = Investment(
            name: "AAPL",
            investmentType: .positive,
            category: .stocks,
            amount: 0,
            currency: "USD"
        )

        investment.marketQuantity = 10
        investment.lastKnownUnitPrice = 150
        investment.totalPurchaseCost = 1000

        #expect(abs((investment.positionGrowthAbsolute ?? 0) - 500) < 0.0001)
        #expect(abs((investment.positionGrowthPercent ?? 0) - 50) < 0.0001)

        investment.totalPurchaseCost = 0
        #expect(investment.positionGrowthAbsolute == nil)
        #expect(investment.positionGrowthPercent == nil)
    }
}
