import Foundation
import Testing
@testable import millio

struct TwelveDataClientTests {
    @Test("Backend market search декодируется в совместимую символ-модель")
    func testSearchResponseDecoding() throws {
        let json = """
        [
          {
            "symbol": "AAPL",
            "name": "Apple Inc",
            "exchange": "NASDAQ",
            "micCode": "XNAS",
            "instrumentType": "Common Stock",
            "country": "United States",
            "currency": "USD"
          }
        ]
        """

        let decoded = try JSONDecoder().decode([MarketSearchResult].self, from: Data(json.utf8))
        let item = try #require(decoded.first?.asSymbol)

        #expect(item.symbol == "AAPL")
        #expect(item.instrumentName == "Apple Inc")
        #expect(item.exchange == "NASDAQ")
        #expect(item.micCode == "XNAS")
        #expect(item.instrumentType == "Common Stock")
        #expect(item.country == "United States")
        #expect(item.currency == "USD")
    }

    @Test("AssetSummary декодирует snapshot backend quote")
    func testAssetSummaryDecoding() throws {
        let json = """
        {
          "symbol": "AAPL",
          "name": "Apple Inc.",
          "exchange": "NASDAQ",
          "micCode": "XNAS",
          "currency": "USD",
          "price": 213.55,
          "previousClose": 210.12,
          "change": 3.43,
          "percentChange": 1.63,
          "isMarketOpen": true,
          "updatedAt": "2026-03-08T12:00:00.000Z",
          "isStale": false
        }
        """

        let decoded = try JSONDecoder().decode(AssetSummary.self, from: Data(json.utf8))

        #expect(decoded.symbol == "AAPL")
        #expect(decoded.price == 213.55)
        #expect(decoded.updatedAt == "2026-03-08T12:00:00.000Z")
        #expect(decoded.isStale == false)
    }

    @Test("MarketAPIClient требует configured auth service")
    func testUnconfiguredClientFails() async {
        let configuration = AuthConfiguration(baseURL: URL(string: "http://localhost:3000/api/v1")!)
        let client = MarketAPIClient(configurationProvider: { configuration })

        await #expect(throws: MarketAPIClientError.unconfigured) {
            _ = try await client.searchSymbols(query: "AAPL")
        }
    }
}
