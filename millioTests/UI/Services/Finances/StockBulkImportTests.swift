import Foundation
import SwiftData
import Testing
import UIKit
@testable import millio

actor StockBulkImportMockMarketDataClient: MarketDataClientProtocol {
    var searchResults: [String: [TwelveDataSymbol]] = [:]
    var latestQuotes: [String: AssetSummary?] = [:]
    var latestPriceErrors: [String: Error] = [:]
    var latestPriceRequests: [(symbol: String, forceRefresh: Bool)] = []

    func setSearchResults(_ results: [TwelveDataSymbol], for query: String) {
        searchResults[query.uppercased()] = results
    }

    func setLatestPrice(_ price: Double?, for symbol: String) {
        latestQuotes[symbol.uppercased()] = AssetSummary(
            symbol: symbol.uppercased(),
            canonicalSymbol: symbol.uppercased(),
            providerSymbol: symbol.uppercased(),
            name: nil,
            exchange: nil,
            micCode: nil,
            currency: "USD",
            price: price,
            previousClose: nil,
            change: nil,
            percentChange: nil,
            isMarketOpen: nil,
            resolutionStatus: .fresh,
            updatedAt: "2026-03-16T00:00:00.000Z",
            isStale: false
        )
        latestPriceErrors.removeValue(forKey: symbol.uppercased())
    }

    func setLatestQuote(_ quote: AssetSummary?, for symbol: String) {
        latestQuotes[symbol.uppercased()] = quote
        latestPriceErrors.removeValue(forKey: symbol.uppercased())
    }

    func setLatestPriceError(_ error: Error, for symbol: String) {
        latestPriceErrors[symbol.uppercased()] = error
        latestQuotes.removeValue(forKey: symbol.uppercased())
    }

    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol] {
        searchResults[query.uppercased()] ?? []
    }

    func latestQuote(symbol: String, forceRefresh: Bool) async throws -> AssetSummary? {
        latestPriceRequests.append((symbol.uppercased(), forceRefresh))
        if let error = latestPriceErrors[symbol.uppercased()] {
            throw error
        }
        return latestQuotes[symbol.uppercased()] ?? nil
    }

    func fetchQuotes(symbols: [String]) async throws -> [AssetSummary] {
        var result: [AssetSummary] = []
        for symbol in symbols {
            let q = try await latestQuote(symbol: symbol, forceRefresh: true)
            if let q {
                result.append(q)
            } else {
                let key = symbol.uppercased()
                result.append(AssetSummary(symbol: key, canonicalSymbol: key, providerSymbol: key, name: nil, exchange: nil, micCode: nil, currency: nil, price: nil, previousClose: nil, change: nil, percentChange: nil, isMarketOpen: nil, resolutionStatus: .notFound, updatedAt: "", isStale: false))
            }
        }
        return result
    }

    func lastLatestPriceRequest() -> (symbol: String, forceRefresh: Bool)? {
        latestPriceRequests.last
    }

    func allLatestPriceRequests() -> [(symbol: String, forceRefresh: Bool)] {
        latestPriceRequests
    }
}

@Suite(.serialized)
@MainActor
struct StockBulkImportTests {
    private struct StubTextRecognizer: StockBulkImportTextRecognizing {
        func recognizeLines(in image: CGImage) async throws -> [String] { [] }
    }

    private static let schema = Schema([
        Investment.self,
        FinanceGroup.self,
        FinanceAccount.self,
    ])
    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
        try context.save()
        return context
    }

    private func assertCurrentPrice(
        _ text: String,
        equals expected: Double
    ) {
        #expect(!text.isEmpty)
        #expect(StockBulkImportNumberParser.parse(text) == expected)
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

    @Test("OCR alias USR нормализуется как US")
    func marketNormalizerHandlesUsrAlias() {
        #expect(StockBulkImportMarketNormalizer.normalize("USR") == "US")
    }

    @Test("Mass import по умолчанию открывается в режиме скриншота")
    func defaultModeIsScreenshot() throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        let viewModel = StockBulkImportViewModel(
            modelContext: context,
            marketDataClient: client,
            parser: StockBulkImportParser(textRecognizer: StubTextRecognizer())
        )

        #expect(viewModel.mode == .screenshot)
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

    @Test("Парсер отбрасывает короткие и служебные OCR токены")
    func parserSkipsShortAndServiceNoiseTokens() {
        let rows = StockBulkImportParser.parseRecognizedLines([
            "ETFs PPLT.US 201.16",
            "X",
            "iShares IBIT.US 40.10",
            "IS"
        ])

        #expect(rows.contains(where: { $0.ticker == "PPLT" }))
        #expect(rows.contains(where: { $0.ticker == "IBIT" }))
        #expect(rows.contains(where: { $0.ticker == "ETFS" }) == false)
        #expect(rows.contains(where: { $0.ticker == "X" }) == false)
        #expect(rows.contains(where: { $0.ticker == "IS" }) == false)
    }

    @Test("mergeDuplicates объединяет строки по market|ticker")
    func mergeDuplicatesUsesMarketAndTickerKey() {
        let candidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple",
            currency: "USD",
            providerRaw: "market-backend"
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

    @Test("Удаление merged preview строки убирает все исходные дубли")
    func removeVisibleRowRemovesAllMergedDuplicates() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        let viewModel = StockBulkImportViewModel(
            modelContext: context,
            marketDataClient: client,
            parser: StockBulkImportParser(textRecognizer: StubTextRecognizer())
        )

        let candidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let spyCandidate = StockBulkImportCandidate(
            symbol: "SPY",
            market: "US",
            displayName: "SPDR S&P 500 ETF Trust",
            currency: "USD",
            providerRaw: "market-backend"
        )

        viewModel.rows = [
            StockBulkImportRowDraft(
                rawLine: "AAPL 2 @ 100",
                tickerText: "AAPL",
                marketText: "NASDAQ",
                quantityText: "2",
                buyPriceText: "100",
                sourceOrderIndex: 0,
                candidates: [candidate],
                selectedCandidate: candidate
            ),
            StockBulkImportRowDraft(
                rawLine: "AAPL 3 @ 110",
                tickerText: "AAPL",
                marketText: "NASDAQ",
                quantityText: "3",
                buyPriceText: "110",
                sourceOrderIndex: 1,
                candidates: [candidate],
                selectedCandidate: candidate
            ),
            StockBulkImportRowDraft(
                rawLine: "SPY 1 @ 600",
                tickerText: "SPY",
                marketText: "US",
                quantityText: "1",
                buyPriceText: "600",
                sourceOrderIndex: 2,
                candidates: [spyCandidate],
                selectedCandidate: spyCandidate
            )
        ]

        let mergedAaplRow = try #require(viewModel.visibleRows.first { $0.selectedCandidate?.normalizedSymbol == "AAPL" })
        viewModel.removeVisibleRow(mergedAaplRow)

        #expect(viewModel.rows.count == 1)
        #expect(viewModel.rows[0].selectedCandidate?.normalizedSymbol == "SPY")
        #expect(viewModel.visibleRows.count == 1)
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

    @Test("Статус priceMissing показывает найденный тикер без текущей цены")
    func rowStatusHighlightsMissingPrice() {
        let candidate = StockBulkImportCandidate(
            symbol: "VXUS",
            market: "US",
            displayName: "Vanguard Total International Stock ETF",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let row = StockBulkImportRowDraft(
            rawLine: "VXUS.US",
            tickerText: "VXUS",
            marketText: "US",
            quantityText: "12",
            buyPriceText: "76.01",
            currentPriceText: "",
            sourceOrderIndex: 0,
            candidates: [candidate],
            selectedCandidate: candidate
        )

        #expect(row.status == .priceMissing)
        #expect(row.requiresAttention)
    }

    @Test("Remote matcher принимает backend symbol с market suffix")
    func matcherAcceptsBackendSuffixSymbol() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setSearchResults([
            TwelveDataSymbol(
                symbol: "VXUS.US",
                instrumentName: "Vanguard Total International Stock ETF",
                exchange: "US",
                micCode: nil,
                instrumentType: "ETF",
                country: "United States",
                currency: "USD"
            )
        ], for: "VXUS")

        let matcher = StockBulkImportMatcher(modelContext: context, marketDataClient: client)
        let rows = await matcher.buildDraftRows(from: [
            StockBulkImportParsedRow(
                rawLine: "VXUS.US",
                ticker: "VXUS",
                market: "US",
                quantity: 12,
                buyPrice: 76.01,
                sourceOrderIndex: 0
            )
        ])

        #expect(rows.count == 1)
        #expect(rows[0].selectedCandidate?.normalizedSymbol == "VXUS")
    }

    @Test("Remote matcher uses shared resolver aliases for company-name queries")
    func matcherUsesSharedResolverAliases() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setSearchResults([
            TwelveDataSymbol(
                symbol: "AAPL",
                instrumentName: "Apple Inc.",
                exchange: "NASDAQ",
                micCode: "XNAS",
                instrumentType: "Common Stock",
                country: "United States",
                currency: "USD"
            )
        ], for: "APPLE")

        let matcher = StockBulkImportMatcher(modelContext: context, marketDataClient: client)
        let rows = await matcher.buildDraftRows(from: [
            StockBulkImportParsedRow(
                rawLine: "Apple",
                ticker: "APPLE",
                market: nil,
                quantity: 1,
                buyPrice: 100,
                sourceOrderIndex: 0
            )
        ])

        #expect(rows.count == 1)
        #expect(rows[0].candidates.first?.normalizedSymbol == "AAPL")
    }

    @Test("Remote matcher prefers requested market using shared candidate policy")
    func matcherPrefersRequestedMarket() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setSearchResults([
            TwelveDataSymbol(
                symbol: "SPY",
                instrumentName: "SPDR S&P 500 ETF Trust",
                exchange: "NYSE",
                micCode: nil,
                instrumentType: "ETF",
                country: "United States",
                currency: "USD"
            ),
            TwelveDataSymbol(
                symbol: "SPY",
                instrumentName: "SPDR S&P 500 ETF Trust",
                exchange: "AMEX",
                micCode: nil,
                instrumentType: "ETF",
                country: "United States",
                currency: "USD"
            )
        ], for: "SPY")

        let matcher = StockBulkImportMatcher(modelContext: context, marketDataClient: client)
        let rows = await matcher.buildDraftRows(from: [
            StockBulkImportParsedRow(
                rawLine: "AMEX SPY",
                ticker: "SPY",
                market: "AMEX",
                quantity: 1,
                buyPrice: 100,
                sourceOrderIndex: 0
            )
        ])

        #expect(rows.count == 1)
        #expect(rows[0].candidates.first?.normalizedMarket == "AMEX")
    }

    @Test("Ручной refresh строки форсирует обновление котировки")
    func refreshCurrentPriceForcesQuoteReload() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setLatestPrice(677.03, for: "SPY.US")
        let viewModel = StockBulkImportViewModel(
            modelContext: context,
            marketDataClient: client,
            parser: StockBulkImportParser(textRecognizer: StubTextRecognizer())
        )

        let candidate = StockBulkImportCandidate(
            symbol: "SPY",
            market: "US",
            displayName: "SPDR S&P 500 ETF Trust",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let rowID = UUID()
        viewModel.rows = [
            StockBulkImportRowDraft(
                id: rowID,
                rawLine: "SPY.US",
                tickerText: "SPY",
                marketText: "US",
                quantityText: "17",
                buyPriceText: "623.55",
                currentPriceText: "",
                sourceOrderIndex: 0,
                candidates: [candidate],
                selectedCandidate: candidate
            )
        ]

        await viewModel.refreshCurrentPrice(for: rowID)

        assertCurrentPrice(viewModel.rows[0].currentPriceText, equals: 677.03)
        let request = await client.lastLatestPriceRequest()
        #expect(request?.symbol == "SPY.US")
        #expect(request?.forceRefresh == true)
    }

    @Test("Частичный провал котировок показывает только проблемные тикеры")
    func warningListsOnlyFailedQuoteSymbols() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setLatestPrice(677.03, for: "SPY.US")
        await client.setLatestPriceError(MarketAPIClientError.transport("offline"), for: "SIVR.US")

        let viewModel = StockBulkImportViewModel(
            modelContext: context,
            marketDataClient: client,
            parser: StockBulkImportParser(textRecognizer: StubTextRecognizer())
        )

        let spy = StockBulkImportCandidate(
            symbol: "SPY",
            market: "US",
            displayName: "SPDR S&P 500 ETF Trust",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let sivr = StockBulkImportCandidate(
            symbol: "SIVR",
            market: "US",
            displayName: "abrdn Physical Silver Shares ETF",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let spyRowID = UUID()
        let sivrRowID = UUID()
        viewModel.rows = [
            StockBulkImportRowDraft(
                id: spyRowID,
                rawLine: "SPY.US",
                tickerText: "SPY",
                marketText: "US",
                quantityText: "17",
                buyPriceText: "623.55",
                currentPriceText: "",
                sourceOrderIndex: 0,
                candidates: [spy],
                selectedCandidate: spy
            ),
            StockBulkImportRowDraft(
                id: sivrRowID,
                rawLine: "SIVR.US",
                tickerText: "SIVR",
                marketText: "US",
                quantityText: "67",
                buyPriceText: "59.02",
                currentPriceText: "",
                sourceOrderIndex: 1,
                candidates: [sivr],
                selectedCandidate: sivr
            )
        ]

        await viewModel.refreshCurrentPrice(for: spyRowID)
        await viewModel.refreshCurrentPrice(for: sivrRowID)

        assertCurrentPrice(viewModel.rows[0].currentPriceText, equals: 677.03)
        #expect(viewModel.rows[1].currentPriceText.isEmpty)
        #expect(viewModel.marketDataWarning?.contains("SIVR") == true)
        #expect(viewModel.marketDataWarning?.contains("SPY") == false)
        #expect(
            viewModel.marketDataWarning?.contains(
                MarketDataErrorPresentation.listLabel(for: .networkError, locale: .current)
            ) == true
        )
    }

    @Test("Mass import различает provider error и отсутствие текущей цены")
    func marketWarningSeparatesProviderAndPriceUnavailable() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setLatestQuote(
            AssetSummary(
                symbol: "NASDAQ:QQQ",
                canonicalSymbol: "QQQ",
                providerSymbol: "QQQ",
                name: nil,
                exchange: "NASDAQ",
                micCode: nil,
                currency: "USD",
                price: nil,
                previousClose: nil,
                change: nil,
                percentChange: nil,
                isMarketOpen: nil,
                resolutionStatus: .providerError,
                updatedAt: "2026-03-16T00:00:00.000Z",
                isStale: false
            ),
            for: "NASDAQ:QQQ"
        )
        await client.setLatestQuote(
            AssetSummary(
                symbol: "NYSE:SIVR",
                canonicalSymbol: "SIVR",
                providerSymbol: "SIVR",
                name: nil,
                exchange: "NYSE",
                micCode: nil,
                currency: "USD",
                price: nil,
                previousClose: nil,
                change: nil,
                percentChange: nil,
                isMarketOpen: nil,
                resolutionStatus: .fresh,
                updatedAt: "2026-03-16T00:00:00.000Z",
                isStale: false
            ),
            for: "NYSE:SIVR"
        )

        let viewModel = StockBulkImportViewModel(
            modelContext: context,
            marketDataClient: client,
            parser: StockBulkImportParser(textRecognizer: StubTextRecognizer())
        )

        let qqq = StockBulkImportCandidate(
            symbol: "QQQ",
            market: "NASDAQ",
            displayName: "Invesco QQQ Trust",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let sivr = StockBulkImportCandidate(
            symbol: "SIVR",
            market: "NYSE",
            displayName: "abrdn Physical Silver Shares ETF",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let qqqRowID = UUID()
        let sivrRowID = UUID()
        viewModel.rows = [
            StockBulkImportRowDraft(
                id: qqqRowID,
                rawLine: "NASDAQ:QQQ",
                tickerText: "QQQ",
                marketText: "NASDAQ",
                quantityText: "3",
                buyPriceText: "400",
                currentPriceText: "",
                sourceOrderIndex: 0,
                candidates: [qqq],
                selectedCandidate: qqq
            ),
            StockBulkImportRowDraft(
                id: sivrRowID,
                rawLine: "NYSE:SIVR",
                tickerText: "SIVR",
                marketText: "NYSE",
                quantityText: "5",
                buyPriceText: "24",
                currentPriceText: "",
                sourceOrderIndex: 1,
                candidates: [sivr],
                selectedCandidate: sivr
            )
        ]

        await viewModel.refreshCurrentPrice(for: qqqRowID)
        await viewModel.refreshCurrentPrice(for: sivrRowID)

        #expect(viewModel.marketDataWarning?.contains("QQQ") == true)
        #expect(viewModel.marketDataWarning?.contains("SIVR") == true)
        #expect(
            viewModel.marketDataWarning?.contains(
                MarketDataErrorPresentation.listLabel(for: .providerError, locale: .current)
            ) == true
        )
        #expect(
            viewModel.marketDataWarning?.contains(
                MarketDataErrorPresentation.listLabel(for: .priceUnavailable, locale: .current)
            ) == true
        )
    }

    @Test("Сохранение акций фиксирует USD и корректный баланс")
    func persistenceStoresUsdAndComputesBalanceFromCurrentPrice() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setLatestPrice(150, for: "AAPL")

        let service = StockBulkImportPersistenceService(modelContext: context, marketDataClient: client)
        let candidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple Inc.",
            currency: "USD",
            providerRaw: "market-backend"
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
        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())

        #expect(savedCount == 1)
        #expect(investments.count == 1)
        #expect(accounts.count == 1)
        #expect(groups.count == 1)
        #expect(accounts[0].group != nil)
        #expect(accounts[0].group?.name == String(localized: "finances.group.ungrouped"))
        #expect(investments[0].currency == "USD")
        #expect(investments[0].marketCurrency == "USD")
        #expect(investments[0].marketSymbol == "NASDAQ:AAPL")
        #expect(investments[0].marketQuantity == 2)
        #expect(investments[0].averagePurchaseUnitPrice == 100)
        #expect(investments[0].lastKnownUnitPrice == 150)
        #expect(investments[0].amount == 300)
    }

    @Test("Импорт без mergeDuplicates не создаёт дубликаты FinanceAccount")
    func persistenceWithoutMergeDoesNotDuplicateFinanceAccounts() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()

        let service = StockBulkImportPersistenceService(modelContext: context, marketDataClient: client)
        let candidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple Inc.",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let drafts = [
            StockBulkImportRowDraft(
                rawLine: "NASDAQ: AAPL 1 @ 100",
                tickerText: "AAPL",
                marketText: "NASDAQ",
                quantityText: "1",
                buyPriceText: "100",
                sourceOrderIndex: 0,
                candidates: [candidate],
                selectedCandidate: candidate
            ),
            StockBulkImportRowDraft(
                rawLine: "NASDAQ: AAPL 2 @ 110",
                tickerText: "AAPL",
                marketText: "NASDAQ",
                quantityText: "2",
                buyPriceText: "110",
                sourceOrderIndex: 1,
                candidates: [candidate],
                selectedCandidate: candidate
            )
        ]

        let savedCount = try await service.persist(
            drafts: drafts,
            includeInTotal: true,
            priority: .normal,
            targetGroup: nil,
            mergeDuplicates: false
        )

        let investments = try context.fetch(FetchDescriptor<Investment>())
        let accounts = try context.fetch(FetchDescriptor<FinanceAccount>())

        #expect(savedCount == 2)
        #expect(investments.count == 1)
        #expect(accounts.count == 1)
    }

    @Test("selectCandidate проставляет тикер и рынок в строке")
    func selectCandidateBackfillsTickerAndMarket() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        let viewModel = StockBulkImportViewModel(
            modelContext: context,
            marketDataClient: client,
            parser: StockBulkImportParser(textRecognizer: StubTextRecognizer())
        )

        let rowID = UUID()
        viewModel.rows = [
            StockBulkImportRowDraft(
                id: rowID,
                rawLine: "apple",
                tickerText: "APPLE",
                marketText: "",
                quantityText: "1",
                buyPriceText: "100",
                sourceOrderIndex: 0,
                candidates: [],
                selectedCandidate: nil
            )
        ]

        let candidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple Inc.",
            currency: "USD",
            providerRaw: "market-backend"
        )

        viewModel.selectCandidate(candidate, for: rowID)

        #expect(viewModel.rows[0].tickerText == "AAPL")
        #expect(viewModel.rows[0].marketText == "NASDAQ")
        #expect(viewModel.rows[0].selectedCandidate == candidate)
        #expect(viewModel.rows[0].candidates == [candidate])
    }

    @Test("applySearchResult не переносит name в ticker")
    func applySearchResultUsesSymbolAsTickerText() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        let viewModel = StockBulkImportViewModel(
            modelContext: context,
            marketDataClient: client,
            parser: StockBulkImportParser(textRecognizer: StubTextRecognizer())
        )

        let rowID = UUID()
        viewModel.rows = [
            StockBulkImportRowDraft(
                id: rowID,
                rawLine: "",
                tickerText: "",
                marketText: "",
                quantityText: "1",
                buyPriceText: "100",
                sourceOrderIndex: 0,
                candidates: [],
                selectedCandidate: nil
            )
        ]

        let symbol = TwelveDataSymbol(
            symbol: "AAPL",
            instrumentName: "Apple Inc.",
            exchange: "NASDAQ",
            micCode: nil,
            instrumentType: "Common Stock",
            country: "United States",
            currency: "USD"
        )

        await viewModel.applySearchResult(symbol, for: rowID)

        #expect(viewModel.rows[0].tickerText == "AAPL")
        #expect(viewModel.rows[0].marketText == "NASDAQ")
        #expect(viewModel.rows[0].selectedCandidate?.displayName == "Apple Inc.")
    }

    @Test("displayHeaderSymbol показывает market:symbol, а имя — отдельно")
    func rowDisplaySplitsSymbolAndName() {
        let candidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple Inc.",
            currency: "USD",
            providerRaw: "market-backend"
        )

        let row = StockBulkImportRowDraft(
            rawLine: "AAPL Apple Inc.",
            tickerText: "AAPL",
            marketText: "NASDAQ",
            quantityText: "1",
            buyPriceText: "100",
            sourceOrderIndex: 0,
            candidates: [candidate],
            selectedCandidate: candidate
        )

        #expect(row.displayHeaderSymbol == "AAPL")
        #expect(row.displaySecondaryText == "Apple Inc.")
        #expect(row.shouldShowRawLineAsSecondaryText == false)
    }

    @Test("quoteLookupSymbol нормализует legacy US format для backend котировок")
    func quoteLookupSymbolNormalizesLegacyUsFormat() {
        let usCandidate = StockBulkImportCandidate(
            symbol: "SPY",
            market: "US",
            displayName: "SPDR S&P 500 ETF Trust",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let nasdaqCandidate = StockBulkImportCandidate(
            symbol: "AAPL",
            market: "NASDAQ",
            displayName: "Apple Inc.",
            currency: "USD",
            providerRaw: "market-backend"
        )

        #expect(usCandidate.quoteLookupSymbol == "SPY.US")
        #expect(nasdaqCandidate.quoteLookupSymbol == "AAPL")
        #expect(usCandidate.quoteLookupSymbols == ["SPY.US", "SPY", "US:SPY"])
        #expect(nasdaqCandidate.quoteLookupSymbols == ["AAPL", "AAPL.US", "NASDAQ:AAPL"])
    }

    @Test("Refresh цены пробует fallback форматы market symbol")
    func refreshCurrentPriceFallsBackToAlternateSymbols() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setLatestPrice(nil, for: "SPY")
        await client.setLatestPrice(677.03, for: "SPY.US")

        let viewModel = StockBulkImportViewModel(
            modelContext: context,
            marketDataClient: client,
            parser: StockBulkImportParser(textRecognizer: StubTextRecognizer())
        )

        let candidate = StockBulkImportCandidate(
            symbol: "SPY",
            market: "NYSE",
            displayName: "SPDR S&P 500 ETF Trust",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let rowID = UUID()
        viewModel.rows = [
            StockBulkImportRowDraft(
                id: rowID,
                rawLine: "SPY",
                tickerText: "SPY",
                marketText: "NYSE",
                quantityText: "17",
                buyPriceText: "623.55",
                currentPriceText: "",
                sourceOrderIndex: 0,
                candidates: [candidate],
                selectedCandidate: candidate
            )
        ]

        await viewModel.refreshCurrentPrice(for: rowID)

        assertCurrentPrice(viewModel.rows[0].currentPriceText, equals: 677.03)
        let requests = await client.allLatestPriceRequests()
        #expect(requests.map(\.symbol) == ["SPY", "SPY.US"])
    }

    @Test("Импорт US тикера мерджится с уже существующей позицией из обычного редактора")
    func persistenceMergesWithExistingPlainSymbolAndExchange() async throws {
        let context = try makeContext()
        let client = StockBulkImportMockMarketDataClient()
        await client.setLatestPrice(677.03, for: "SPY.US")

        let existing = Investment(
            name: "SPY",
            investmentType: .positive,
            category: .stocks,
            amount: 1000,
            currency: "USD",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        existing.marketSymbol = "SPY"
        existing.marketExchange = "US"
        existing.marketCurrency = "USD"
        existing.marketQuantity = 10
        existing.averagePurchaseUnitPrice = 600
        existing.totalPurchaseCost = 6000
        existing.lastKnownUnitPrice = 650
        context.insert(existing)

        let account = FinanceAccount(accountType: .investment, accountID: existing.investmentUniqueID)
        context.insert(account)
        try context.save()

        let service = StockBulkImportPersistenceService(modelContext: context, marketDataClient: client)
        let candidate = StockBulkImportCandidate(
            symbol: "SPY",
            market: "US",
            displayName: "SPDR S&P 500 ETF Trust",
            currency: "USD",
            providerRaw: "market-backend"
        )
        let drafts = [
            StockBulkImportRowDraft(
                rawLine: "SPY.US 17 @ 623.55",
                tickerText: "SPY",
                marketText: "US",
                quantityText: "17",
                buyPriceText: "623.55",
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
        #expect(investments[0].marketSymbol == "US:SPY")
        #expect(abs((investments[0].lastKnownUnitPrice ?? 0) - 677.03) < 0.0001)
        #expect(abs((investments[0].marketQuantity ?? 0) - 27) < 0.0001)
    }
}
