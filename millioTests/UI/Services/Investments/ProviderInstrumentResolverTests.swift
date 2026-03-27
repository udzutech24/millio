import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct ProviderInstrumentResolverTests {
    @Test("Provider resolver prefers mapped provider symbol before legacy fallbacks")
    func prefersMappedProviderSymbol() throws {
        let schema = Schema([
            Investment.self,
            AssetProviderMapping.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let investment = Investment(
            name: "Apple",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        investment.assetID = "asset.stocks.aapl"
        investment.marketSymbol = "AAPL"
        investment.marketExchange = "NASDAQ"
        investment.marketQuoteLookupKey = "AAPL"
        context.insert(investment)

        let mapping = AssetProviderMapping(
            mappingID: "asset.stocks.aapl|market-backend|aapl.us|us",
            assetID: "asset.stocks.aapl",
            providerName: "market-backend",
            providerSymbol: "AAPL.US",
            providerExchangeCode: "US",
            providerInstrumentID: nil,
            status: .active,
            lastVerifiedAt: Date()
        )
        context.insert(mapping)
        try context.save()

        let resolver = ProviderInstrumentResolver(modelContext: context)
        let symbols = resolver.quoteLookupSymbols(for: investment)

        #expect(symbols.first == "AAPL.US")
        #expect(symbols.contains("AAPL"))
    }

    @Test("Provider resolver uses single mapped refresh symbol for finance refreshes")
    func prefersSingleMappedRefreshSymbol() throws {
        let schema = Schema([
            Investment.self,
            AssetProviderMapping.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let investment = Investment(
            name: "Apple",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        investment.assetID = "asset.stocks.aapl"
        investment.marketSymbol = "AAPL"
        investment.marketQuoteLookupKey = "AAPL"
        context.insert(investment)

        let mapping = AssetProviderMapping(
            mappingID: "asset.stocks.aapl|market-backend|aapl.us|us",
            assetID: "asset.stocks.aapl",
            providerName: "market-backend",
            providerSymbol: "AAPL.US",
            providerExchangeCode: "US",
            providerInstrumentID: nil,
            status: .active,
            lastVerifiedAt: Date()
        )
        context.insert(mapping)
        try context.save()

        let resolver = ProviderInstrumentResolver(modelContext: context)

        #expect(resolver.preferredRefreshSymbol(for: investment) == "AAPL.US")
    }

    @Test("Provider resolver uses canonical ticker before exchange-prefixed legacy alias")
    func prefersCanonicalTickerForLegacyUSExchangeSymbol() throws {
        let schema = Schema([
            Investment.self,
            AssetProviderMapping.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let investment = Investment(
            name: "SPY",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        investment.marketSymbol = "NYSE:SPY"
        context.insert(investment)
        try context.save()

        let resolver = ProviderInstrumentResolver(modelContext: context)
        let symbols = resolver.quoteLookupSymbols(for: investment)

        #expect(symbols.first == "SPY")
        #expect(symbols.contains("NYSE:SPY"))
    }

    @Test("Provider resolver keeps raw provider-style symbol when no canonical key is stored")
    func keepsRawProviderStyleSymbolWithoutCanonicalKey() throws {
        let schema = Schema([
            Investment.self,
            AssetProviderMapping.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let investment = Investment(
            name: "Gold",
            investmentType: .positive,
            category: .stocks,
            amount: 100,
            currency: "USD"
        )
        investment.marketSymbol = "GLD.US"
        context.insert(investment)
        try context.save()

        let resolver = ProviderInstrumentResolver(modelContext: context)

        #expect(resolver.preferredRefreshSymbol(for: investment) == "GLD.US")
    }
}
