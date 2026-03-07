import Foundation
import SwiftData
import Testing
@testable import millio

actor StockBulkImportMockMarketDataClient: MarketDataClientProtocol {
    var searchResults: [String: [TwelveDataSymbol]] = [:]
    var latestPrices: [String: Double?] = [:]

    func setLatestPrice(_ price: Double?, for symbol: String) {
        latestPrices[symbol.uppercased()] = price
    }

    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol] {
        searchResults[query.uppercased()] ?? []
    }

    func latestPrice(symbol: String, forceRefresh: Bool) async throws -> Double? {
        latestPrices[symbol.uppercased()] ?? nil
    }
}

@Suite(.serialized)
@MainActor
struct StockBulkImportTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func makeContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(FinanceAccount.self)
        try context.deleteAll(FinanceGroup.self)
        try context.deleteAll(Investment.self)
        try context.save()
        return context
    }

    @Test("Парсер поддерживает все основные форматы тикеров")
    func parserSupportsTickerFormats() {
        let rows = StockBulkImportParser.parseRecognizedLines([
            "NASDAQ: AAPL 12 шт по 76.01",
            "NYSE-A",
            "AAPL.US",
            "SBER.MOEX"
        ])

        #expect(rows.contains { $0.ticker == "AAPL" && $0.market == "NASDAQ" })
        #expect(rows.contains { $0.ticker == "A" && $0.market == "NYSE" })
        #expect(rows.contains { $0.ticker == "AAPL" && $0.market == "US" })
        #expect(rows.contains { $0.ticker == "SBER" && $0.market == "MOEX" })
    }

    @Test("Парсер извлекает quantity и price из соседних строк")
    func parserExtractsAdjacentQuantityAndPrice() {
        let rows = StockBulkImportParser.parseRecognizedLines([
            "AAPL",
            "12 шт. по 76.01",
            "MSFT",
            "Qty 3 shares @ 120.5"
        ])

        let aapl = rows.first { $0.ticker == "AAPL" }
        let msft = rows.first { $0.ticker == "MSFT" }

        #expect(aapl?.quantity == 12)
        #expect(abs((aapl?.buyPrice ?? 0) - 76.01) < 0.0001)
        #expect(msft?.quantity == 3)
        #expect(abs((msft?.buyPrice ?? 0) - 120.5) < 0.0001)
    }

    @Test("Парсер поддерживает брокерский список и игнорирует шапку счёта")
    func parserSupportsBrokerListLayout() {
        let rows = StockBulkImportParser.parseRecognizedLines([
            "AM #1468105",
            "SPDR SPY.US 671.50",
            "17 шт. по 623.55 11 415.50 +7.69%",
            "GLD.US 475.46",
            "19 шт. по 344.24 9 033.74 +38.12%"
        ])

        let spy = rows.first { $0.ticker == "SPY" }
        let gld = rows.first { $0.ticker == "GLD" }

        #expect(rows.contains(where: { $0.ticker == "AM" }) == false)
        #expect(spy?.market == "US")
        #expect(spy?.quantity == 17)
        #expect(abs((spy?.buyPrice ?? 0) - 623.55) < 0.0001)
        #expect(gld?.market == "US")
        #expect(gld?.quantity == 19)
        #expect(abs((gld?.buyPrice ?? 0) - 344.24) < 0.0001)
    }

    @Test("mergeDuplicates объединяет строки по market|ticker")
    func mergeDuplicatesUsesMarketAndTickerKey() {
        let candidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple",
            currency: "USD",
            providerRaw: "twelvedata"
        )
        let drafts = [
            StockBulkImportRowDraft(
                rawLine: "AAPL",
                tickerText: "AAPL",
                marketText: "NASDAQ",
                quantityText: "2",
                buyPriceText: "100",
                sourceOrderIndex: 0,
                candidates: [candidate],
                selectedCandidate: candidate
            ),
            StockBulkImportRowDraft(
                rawLine: "AAPL",
                tickerText: "AAPL",
                marketText: "NASDAQ",
                quantityText: "3",
                buyPriceText: "110",
                sourceOrderIndex: 1,
                candidates: [candidate],
                selectedCandidate: candidate
            )
        ]

        let merged = StockBulkImportPersistenceService.mergeAddableRows(from: drafts)

        #expect(merged.count == 1)
        #expect(merged[0].quantity == 5)
        #expect(merged[0].buyPrice == 100)
    }

    @Test("Строка addable только при found + qty + buyPrice")
    func rowValidationRequiresCandidateQuantityAndBuyPrice() {
        let candidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple",
            currency: "USD",
            providerRaw: nil
        )

        let valid = StockBulkImportRowDraft(
            rawLine: "AAPL",
            tickerText: "AAPL",
            marketText: "",
            quantityText: "1",
            buyPriceText: "0",
            sourceOrderIndex: 0,
            candidates: [candidate],
            selectedCandidate: candidate
        )
        let missingPrice = StockBulkImportRowDraft(
            rawLine: "AAPL",
            tickerText: "AAPL",
            marketText: "",
            quantityText: "1",
            buyPriceText: "",
            sourceOrderIndex: 1,
            candidates: [candidate],
            selectedCandidate: candidate
        )
        let ambiguous = StockBulkImportRowDraft(
            rawLine: "AAPL",
            tickerText: "AAPL",
            marketText: "",
            quantityText: "1",
            buyPriceText: "10",
            sourceOrderIndex: 2,
            candidates: [candidate],
            selectedCandidate: nil
        )

        #expect(valid.isAddable)
        #expect(!missingPrice.isAddable)
        #expect(!ambiguous.isAddable)
    }

    @Test("Сохранение акций фиксирует USD и корректный баланс")
    func persistenceStoresUsdAndComputesBalanceFromCurrentPrice() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setLatestPrice(150, for: "NASDAQ:AAPL")

        let service = StockBulkImportPersistenceService(modelContext: context, marketDataClient: client)
        let candidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple Inc.",
            currency: "USD",
            providerRaw: "twelvedata"
        )
        let drafts = [
            StockBulkImportRowDraft(
                rawLine: "NASDAQ: AAPL 2 @ 100",
                tickerText: "AAPL",
                marketText: "NASDAQ",
                quantityText: "2",
                buyPriceText: "100",
                sourceOrderIndex: 0,
                candidates: [candidate],
                selectedCandidate: candidate
            )
        ]

        let savedCount = try await service.persist(
            drafts: drafts,
            includeInTotal: true,
            priority: .normal,
            targetGroup: nil,
            mergeDuplicates: true
        )

        let investments = try context.fetch(FetchDescriptor<Investment>())
        let accounts = try context.fetch(FetchDescriptor<FinanceAccount>())

        #expect(savedCount == 1)
        #expect(investments.count == 1)
        #expect(accounts.count == 1)
        #expect(investments[0].currency == "USD")
        #expect(investments[0].marketCurrency == "USD")
        #expect(investments[0].marketSymbol == "NASDAQ:AAPL")
        #expect(investments[0].marketQuantity == 2)
        #expect(investments[0].averagePurchaseUnitPrice == 100)
        #expect(investments[0].lastKnownUnitPrice == 150)
        #expect(investments[0].amount == 300)
    }
}
