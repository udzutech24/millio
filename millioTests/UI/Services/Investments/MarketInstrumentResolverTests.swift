import Foundation
import Testing
@testable import millio

private actor MarketInstrumentResolverClientMock: MarketDataClientProtocol {
    let symbols: [TwelveDataSymbol]

    init(symbols: [TwelveDataSymbol]) {
        self.symbols = symbols
    }

    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol] {
        symbols
    }

    func latestQuote(symbol: String, forceRefresh: Bool) async throws -> AssetSummary? {
        nil
    }
}

@Suite(.serialized)
@MainActor
struct MarketInstrumentResolverTests {
    @Test("Resolver returns the same local-first instruments as the search sheet")
    func resolverUsesSharedLocalIndex() async throws {
        let resolver = MarketInstrumentResolver(
            client: MarketInstrumentResolverClientMock(symbols: [])
        )

        let results = try await resolver.resolveSymbols(
            query: "tesla",
            filter: .stocks,
            outputSize: 10
        )

        #expect(results.first?.symbol == "TSLA")
    }

    @Test("Resolver keeps provider suffix instruments aligned for bulk-import consumers")
    func resolverSupportsProviderSuffixResults() async throws {
        let resolver = MarketInstrumentResolver(
            client: MarketInstrumentResolverClientMock(symbols: [
                TwelveDataSymbol(
                    symbol: "VXUS.US",
                    instrumentName: "Vanguard Total International Stock ETF",
                    exchange: "US",
                    micCode: nil,
                    instrumentType: "ETF",
                    country: "United States",
                    currency: "USD"
                )
            ])
        )

        let results = try await resolver.resolveSymbols(
            query: "vxus",
            filter: .stocks,
            outputSize: 10
        )

        #expect(results.first?.symbol == "VXUS.US")
    }
}
