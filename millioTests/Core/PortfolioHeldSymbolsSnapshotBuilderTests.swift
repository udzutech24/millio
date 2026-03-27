import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct PortfolioHeldSymbolsSnapshotBuilderTests {
    @Test("Snapshot includes only active holdings symbols and deduplicates them")
    func testBuildFiltersAndDeduplicatesHeldSymbols() {
        let stock = Investment(
            name: "S&P 500",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        stock.marketSymbol = " spy "
        stock.marketQuantity = 2

        let duplicateStock = Investment(
            name: "S&P 500 Duplicate",
            investmentType: .positive,
            category: .stocks,
            amount: 120,
            currency: "USD"
        )
        duplicateStock.marketSymbol = "SPY"

        let crypto = Investment(
            name: "Bitcoin",
            investmentType: .positive,
            category: .crypto,
            amount: 50,
            currency: "USD"
        )
        crypto.marketSymbol = "btc/usd"
        crypto.marketQuantity = 0.25

        let archived = Investment(
            name: "Archived",
            investmentType: .positive,
            category: .stocks,
            amount: 20,
            currency: "USD"
        )
        archived.marketSymbol = "QQQ"
        archived.archivedAt = Date()

        let watchlistLike = Investment(
            name: "No Quantity Position",
            investmentType: .positive,
            category: .other,
            amount: 5,
            currency: "USD"
        )
        watchlistLike.marketSymbol = "GLD"

        let soldOut = Investment(
            name: "Sold Out",
            investmentType: .positive,
            category: .stocks,
            amount: 0,
            currency: "USD"
        )
        soldOut.marketSymbol = "ORCL"
        soldOut.marketQuantity = 0

        let symbols = PortfolioHeldSymbolsSnapshotBuilder.build(
            from: [stock, duplicateStock, crypto, archived, watchlistLike, soldOut]
        )

        #expect(symbols == ["BTC/USD", "SPY"])
    }

    @Test("Legacy market holdings without quantity are still synced")
    func testBuildKeepsLegacyHoldingWithoutQuantity() {
        let legacyHolding = Investment(
            name: "Oracle",
            investmentType: .positive,
            category: .stocks,
            amount: 500,
            currency: "USD"
        )
        legacyHolding.marketSymbol = "orcl"
        legacyHolding.marketQuantity = nil

        let symbols = PortfolioHeldSymbolsSnapshotBuilder.build(from: [legacyHolding])

        #expect(symbols == ["ORCL"])
    }
}
