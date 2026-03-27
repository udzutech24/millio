import Foundation
import Testing
@testable import millio

struct MarketSymbolIdentityTests {
    @Test("SPY uses canonical requested symbol")
    func stockIdentityUsesCanonicalRequestedSymbol() throws {
        let investment = Investment(
            name: "SPY",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        investment.marketSymbol = "NYSE:SPY"
        investment.marketQuoteLookupKey = "SPY"
        investment.assetID = "asset.stocks.spy"

        let identity = try #require(MarketSymbolIdentity(investment: investment))

        #expect(identity.requestedSymbol == "SPY")
        #expect(identity.canonicalSymbol == "SPY")
        #expect(identity.assetID == "asset.stocks.spy")
    }

    @Test("QQQ falls back to canonical symbol when quote lookup key is missing")
    func stockIdentityFallsBackToCanonicalKey() throws {
        let identity = try #require(
            MarketSymbolIdentity(
                marketSymbol: "NASDAQ:QQQ",
                exchange: "NASDAQ",
                quoteLookupKey: nil
            )
        )

        #expect(identity.requestedSymbol == "QQQ")
        #expect(identity.canonicalSymbol == nil)
    }

    @Test("BTC/USD keeps pair symbol without alias cascade")
    func cryptoIdentityKeepsRequestedPair() throws {
        let identity = try #require(
            MarketSymbolIdentity(
                marketSymbol: "BTC/USD",
                exchange: nil,
                quoteLookupKey: "BTC/USD"
            )
        )

        #expect(identity.requestedSymbol == "BTC/USD")
        #expect(identity.canonicalSymbol == "BTC/USD")
    }
}
