import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct MarketAssetCatalogTests {
    @Test("Resolver стабилизирует assetID для разных provider symbol форм одного US тикера")
    func resolvesStableAssetIDForProviderVariants() {
        let plain = MarketAssetIdentityResolver.resolve(
            category: .stocks,
            symbol: "AAPL",
            exchange: "NASDAQ",
            instrumentName: "Apple Inc.",
            micCode: "XNAS",
            instrumentType: "Common Stock",
            currency: "USD",
            country: "United States",
            providerName: "twelve-data"
        )
        let suffixed = MarketAssetIdentityResolver.resolve(
            category: .stocks,
            symbol: "AAPL.US",
            exchange: "US",
            instrumentName: "Apple Inc.",
            micCode: "XNAS",
            instrumentType: "Common Stock",
            currency: "USD",
            country: "United States",
            providerName: "another-provider"
        )

        #expect(plain?.assetID == suffixed?.assetID)
        #expect(plain?.canonicalSymbol == "AAPL")
    }

    @Test("Asset catalog store upserts item and provider mapping without duplicates")
    func assetCatalogStoreUpsertsModels() throws {
        let schema = Schema([
            AssetCatalogItem.self,
            AssetProviderMapping.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let store = AssetCatalogStore(modelContext: context)

        let identity = try #require(MarketAssetIdentityResolver.resolve(
            category: .crypto,
            symbol: "BTC/USD",
            exchange: "CRYPTO",
            instrumentName: "Bitcoin / US Dollar",
            micCode: nil,
            instrumentType: "Cryptocurrency",
            currency: "USD",
            country: nil,
            providerName: "market-backend"
        ))

        store.sync(identity: identity)
        store.sync(identity: identity)

        let assets = try context.fetch(FetchDescriptor<AssetCatalogItem>())
        let mappings = try context.fetch(FetchDescriptor<AssetProviderMapping>())

        #expect(assets.count == 1)
        #expect(mappings.count == 1)
        #expect(assets.first?.assetID == identity.assetID)
        #expect(mappings.first?.assetID == identity.assetID)
    }

    @Test("Asset catalog store gracefully skips sync when schema does not include catalog models")
    func assetCatalogStoreSkipsUnsupportedSchema() throws {
        let schema = Schema([Investment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let store = AssetCatalogStore(modelContext: context)
        let identity = try #require(MarketAssetIdentityResolver.resolve(
            category: .stocks,
            symbol: "AAPL",
            exchange: "NASDAQ",
            instrumentName: "Apple Inc.",
            micCode: "XNAS",
            instrumentType: "Common Stock",
            currency: "USD",
            country: "United States",
            providerName: "market-backend"
        ))

        let didSync = store.syncIfSupported(identity: identity)

        #expect(didSync == false)
    }

    @Test("Investment export сохраняет internal assetID")
    func investmentExportIncludesAssetID() throws {
        let investment = Investment(
            name: "Apple",
            investmentType: .positive,
            category: .stocks,
            amount: 1000,
            currency: "USD"
        )
        investment.assetID = "asset.stocks.aapl"
        investment.marketSymbol = "AAPL"

        let data = try investment.export()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["assetID"] as? String == "asset.stocks.aapl")
    }
}
