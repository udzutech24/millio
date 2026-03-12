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
}
