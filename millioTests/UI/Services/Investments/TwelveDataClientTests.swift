import Foundation
import Testing
@testable import millio

struct TwelveDataClientTests {
    @Test("TwelveData search response декодируется из реального JSON")
    func testSearchResponseDecoding() throws {
        let json = """
        {
          "data": [
            {
              "symbol": "AAPL",
              "instrument_name": "Apple Inc",
              "exchange": "NASDAQ",
              "mic_code": "XNAS",
              "instrument_type": "Common Stock",
              "country": "United States",
              "currency": "USD"
            }
          ],
          "status": "ok"
        }
        """

        let decoded = try JSONDecoder().decode(TwelveDataSearchResponse.self, from: Data(json.utf8))
        let item = try #require(decoded.data?.first)

        #expect(item.symbol == "AAPL")
        #expect(item.instrumentName == "Apple Inc")
        #expect(item.exchange == "NASDAQ")
        #expect(item.micCode == "XNAS")
        #expect(item.instrumentType == "Common Stock")
        #expect(item.country == "United States")
        #expect(item.currency == "USD")
    }

    @Test("TwelveData price response декодирует success и error")
    func testPriceResponseDecoding() throws {
        let successJSON = """
        {
          "price": "45123.55"
        }
        """

        let errorJSON = """
        {
          "status": "error",
          "code": 400,
          "message": "**symbol** parameter is required."
        }
        """

        let success = try JSONDecoder().decode(TwelveDataPriceResponse.self, from: Data(successJSON.utf8))
        let error = try JSONDecoder().decode(TwelveDataPriceResponse.self, from: Data(errorJSON.utf8))

        #expect(success.price == "45123.55")
        #expect(success.status == nil)

        #expect(error.status == "error")
        #expect(error.code == 400)
        #expect(error.message == "**symbol** parameter is required.")
    }

    @Test("TwelveDataClient возвращает soft error при отсутствии API ключа")
    func testMissingAPIKeyError() async {
        let client = TwelveDataClient(apiKeyProvider: { nil })

        await #expect(throws: TwelveDataClientError.missingAPIKey) {
            _ = try await client.searchSymbols(query: "AAPL")
        }
    }
}
