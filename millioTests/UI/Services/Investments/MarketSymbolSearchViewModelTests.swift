import Foundation
import Testing
@testable import millio

private actor MarketSymbolSearchClientMock: MarketDataClientProtocol {
    let symbols: [TwelveDataSymbol]
    let error: Error?
    private(set) var queries: [String] = []

    init(symbols: [TwelveDataSymbol], error: Error? = nil) {
        self.symbols = symbols
        self.error = error
    }

    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol] {
        queries.append(query)
        if let error {
            throw error
        }
        return symbols
    }

    func latestPrice(symbol: String, forceRefresh: Bool) async throws -> Double? {
        nil
    }

    func recordedQueries() -> [String] {
        queries
    }
}

@Suite(.serialized)
@MainActor
struct MarketSymbolSearchViewModelTests {
    @Test("Search engine skips remote search for strong local exact matches")
    func skipsRemoteForStrongLocalMatch() {
        let localResults = MarketSymbolSearchEngine.localResults(filter: .stocks, query: "tesla")

        #expect(MarketSymbolSearchEngine.shouldSkipRemoteSearch(filter: .stocks, query: "tesla", localResults: localResults))
    }

    @Test("Search engine находит популярные активы по alias и мисспеллам")
    func findsPopularAssetsByAlias() {
        let apple = MarketSymbolSearchEngine.prepareResults(
            remoteSymbols: [],
            filter: .stocks,
            query: "apple"
        )
        let bitcoin = MarketSymbolSearchEngine.prepareResults(
            remoteSymbols: [],
            filter: .crypto,
            query: "btc"
        )
        let sp500 = MarketSymbolSearchEngine.prepareResults(
            remoteSymbols: [],
            filter: .stocks,
            query: "sp500"
        )
        let gold = MarketSymbolSearchEngine.prepareResults(
            remoteSymbols: [],
            filter: .stocks,
            query: "gold"
        )

        #expect(apple.first?.symbol == "AAPL")
        #expect(bitcoin.first?.symbol == "BTC/USD")
        #expect(sp500.first?.symbol == "SPY")
        #expect(gold.first?.symbol == "GLD")
    }

    @Test("Top quick picks for stocks expose six rows of popular symbols")
    func topQuickPicksExposeSixRows() {
        let topSymbols = MarketSymbolFilter.stocks.topSymbols

        #expect(topSymbols.count == 24)
        #expect(Array(topSymbols.prefix(4)).map(\.symbol) == ["AAPL", "SPY", "MSFT", "NVDA"])
        #expect(Array(topSymbols.suffix(4)).map(\.symbol) == ["IVV", "VTI", "ORCL", "COST"])
    }

    @Test("Formatter убирает точные дубли тикеров и сохраняет уникальные рынки")
    func deduplicatesExactDuplicates() {
        let duplicated = [
            TwelveDataSymbol(symbol: "QQQ", instrumentName: "Invesco QQQ Trust", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD"),
            TwelveDataSymbol(symbol: "QQQ", instrumentName: "Invesco QQQ Trust", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD"),
            TwelveDataSymbol(symbol: "QQQ", instrumentName: "Invesco QQQ Trust", exchange: "BATS", micCode: "BATS", instrumentType: "ETF", country: "United States", currency: "USD"),
            TwelveDataSymbol(symbol: "QQQM", instrumentName: "Invesco NASDAQ 100 ETF", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD")
        ]

        let prepared = MarketSymbolSearchFormatter.prepareResults(
            duplicated,
            filter: .stocks,
            query: "qqq"
        )

        #expect(prepared.map(\.symbol) == ["QQQ", "QQQ", "QQQM"])
    }

    @Test("Formatter поднимает точное совпадение тикера выше частичных результатов")
    func ranksExactSymbolFirst() {
        let symbols = [
            TwelveDataSymbol(symbol: "TQQQ", instrumentName: "ProShares UltraPro QQQ", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD"),
            TwelveDataSymbol(symbol: "QQQM", instrumentName: "Invesco NASDAQ 100 ETF", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD"),
            TwelveDataSymbol(symbol: "QQQ", instrumentName: "Invesco QQQ Trust", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD")
        ]

        let prepared = MarketSymbolSearchFormatter.prepareResults(
            symbols,
            filter: .stocks,
            query: "QQQ"
        )

        #expect(prepared.first?.symbol == "QQQ")
    }

    @Test("Search engine поднимает exact alias выше сырого провайдерного шума")
    func ranksAliasAboveProviderNoise() {
        let prepared = MarketSymbolSearchEngine.prepareResults(
            remoteSymbols: [
                TwelveDataSymbol(symbol: "BTCB", instrumentName: "Random Small Cap", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "BTC/USD", instrumentName: "Bitcoin / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD")
            ],
            filter: .crypto,
            query: "btc"
        )

        #expect(prepared.first?.symbol == "BTC/USD")
    }

    @Test("ViewModel применяет дедупликацию к ответу поиска")
    func viewModelAppliesDeduplication() async throws {
        let client = MarketSymbolSearchClientMock(symbols: [
            TwelveDataSymbol(symbol: "QQQ", instrumentName: "Invesco QQQ Trust", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD"),
            TwelveDataSymbol(symbol: "QQQ", instrumentName: "Invesco QQQ Trust", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD"),
            TwelveDataSymbol(symbol: "QQQI", instrumentName: "NEOS Nasdaq-100 High Income ETF", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD")
        ])

        let viewModel = MarketSymbolSearchViewModel(client: client, filter: .stocks)
        viewModel.searchText = "QQQX"
        viewModel.updateSearch()

        try await Task.sleep(for: .milliseconds(700))

        #expect(viewModel.results.map(\.symbol) == ["QQQ", "QQQI"])
    }

    @Test("ViewModel может найти локальный alias даже если провайдер ничего не вернул")
    func viewModelUsesLocalAliasIndex() async throws {
        let client = MarketSymbolSearchClientMock(symbols: [])

        let viewModel = MarketSymbolSearchViewModel(client: client, filter: .stocks)
        viewModel.searchText = "tesla"
        viewModel.updateSearch()

        try await Task.sleep(for: .milliseconds(350))

        #expect(viewModel.results.first?.symbol == "TSLA")
    }

    @Test("ViewModel не идет в remote search на односимвольный ввод")
    func viewModelUsesMinimumQueryLength() {
        let viewModel = MarketSymbolSearchViewModel(
            client: MarketSymbolSearchClientMock(symbols: []),
            filter: .stocks
        )

        viewModel.searchText = "v"
        viewModel.updateSearch()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.results.isEmpty)
        #expect(
            viewModel.emptyStateHintText ==
            String(
                format: String(localized: "finances.market.search.min_chars_format"),
                MarketSymbolSearchViewModel.minimumRemoteQueryLength
            )
        )
    }

    @Test("ViewModel скрывает raw throttle error и сохраняет локальные результаты")
    func viewModelHandlesRateLimitGracefully() async throws {
        let client = MarketSymbolSearchClientMock(
            symbols: [],
            error: MarketAPIClientError.backend(statusCode: 429, message: "ThrottleException: Too Many Requests")
        )

        let viewModel = MarketSymbolSearchViewModel(client: client, filter: .stocks)
        viewModel.searchText = "tesla"
        viewModel.updateSearch()

        try await Task.sleep(for: .milliseconds(650))

        #expect(viewModel.results.first?.symbol == "TSLA")
        #expect(viewModel.errorMessage == nil)
    }

    @Test("ViewModel uses cached query results immediately while revalidating in background")
    func viewModelUsesCachedResultsImmediately() async throws {
        let remoteResults = [
            TwelveDataSymbol(symbol: "VXUS", instrumentName: "Vanguard Total International Stock ETF", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD")
        ]
        let client = MarketSymbolSearchClientMock(symbols: remoteResults)
        let viewModel = MarketSymbolSearchViewModel(client: client, filter: .stocks)

        viewModel.searchText = "vxus"
        viewModel.updateSearch()
        try await Task.sleep(for: .milliseconds(650))

        #expect(viewModel.results.first?.symbol == "VXUS")

        viewModel.updateSearch()

        #expect(viewModel.results.first?.symbol == "VXUS")
        #expect(viewModel.isLoading == true)

        let queries = await client.recordedQueries()
        #expect(queries == ["vxus"])
    }
}
