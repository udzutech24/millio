import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct PortfolioHeldSymbolsSnapshotBuilderTests {
    private func marketAccount(
        name: String,
        symbol: String,
        assetClass: MarketAssetClass = .stock,
        archived: Bool = false
    ) -> Account {
        let account = Account(name: name, kind: .marketInvestment, currency: "USD")
        account.marketMeta = MarketMeta(symbol: symbol, assetClass: assetClass)
        if archived { account.archivedAt = Date() }
        return account
    }

    @Test("Snapshot includes only active market accounts symbols and deduplicates them")
    func testBuildFiltersAndDeduplicatesHeldSymbols() {
        let stock = marketAccount(name: "S&P 500", symbol: " spy ")
        let duplicateStock = marketAccount(name: "S&P 500 Duplicate", symbol: "SPY")
        let crypto = marketAccount(name: "Bitcoin", symbol: "btc/usd", assetClass: .crypto)
        let archived = marketAccount(name: "Archived", symbol: "QQQ", archived: true)

        // Не рыночный счёт — символ не должен попадать в снэпшот.
        let cashWithSymbol = Account(name: "Cash", kind: .cash, currency: "USD")
        cashWithSymbol.marketMeta = MarketMeta(symbol: "GLD", assetClass: .stock)

        let symbols = PortfolioHeldSymbolsSnapshotBuilder.build(
            from: [stock, duplicateStock, crypto, archived, cashWithSymbol]
        )

        #expect(symbols == ["BTC/USD", "SPY"])
    }

    @Test("Active market account symbol is normalized and included")
    func testBuildNormalizesSymbol() {
        let holding = marketAccount(name: "Oracle", symbol: "orcl")

        let symbols = PortfolioHeldSymbolsSnapshotBuilder.build(from: [holding])

        #expect(symbols == ["ORCL"])
    }

    @Test("Empty or whitespace-only symbols are dropped")
    func testBuildDropsEmptySymbols() {
        let blank = marketAccount(name: "Blank", symbol: "   ")

        let symbols = PortfolioHeldSymbolsSnapshotBuilder.build(from: [blank])

        #expect(symbols.isEmpty)
    }
}
