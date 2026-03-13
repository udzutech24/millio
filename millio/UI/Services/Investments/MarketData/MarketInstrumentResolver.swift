import Foundation

@MainActor
final class MarketInstrumentResolver {
    private let client: MarketDataClientProtocol
    private var cachedResultsByKey: [String: [TwelveDataSymbol]] = [:]

    init(client: MarketDataClientProtocol) {
        self.client = client
    }

    func localResults(
        query: String,
        filter: MarketSymbolFilter
    ) -> [TwelveDataSymbol] {
        MarketSymbolSearchEngine.localResults(filter: filter, query: query)
    }

    func resolveSymbols(
        query: String,
        filter: MarketSymbolFilter,
        outputSize: Int = 30
    ) async throws -> [TwelveDataSymbol] {
        let normalizedQuery = MarketSymbolSearchEngine.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let localResults = MarketSymbolSearchEngine.localResults(filter: filter, query: query)
        let cacheKey = makeCacheKey(query: normalizedQuery, filter: filter)
        let cachedResults = cachedResultsByKey[cacheKey] ?? []

        if normalizedQuery.count < MarketSymbolSearchEngine.minimumRemoteQueryLength ||
            MarketSymbolSearchEngine.shouldSkipRemoteSearch(
                filter: filter,
                query: normalizedQuery,
                localResults: localResults
            ) {
            return Array(
                MarketSymbolSearchEngine.prepareResults(
                    remoteSymbols: cachedResults,
                    filter: filter,
                    query: normalizedQuery
                )
                .prefix(max(1, outputSize))
            )
        }

        do {
            let remoteResults = try await client.searchSymbols(query: query, outputSize: outputSize)
            cachedResultsByKey[cacheKey] = remoteResults
            let prepared = MarketSymbolSearchEngine.prepareResults(
                remoteSymbols: remoteResults,
                filter: filter,
                query: normalizedQuery
            )
            let prioritized = MarketSymbolSearchEngine.prioritizeProviderSuffixMatches(
                prepared,
                query: normalizedQuery
            )
            return Array(prioritized.prefix(max(1, outputSize)))
        } catch {
            let fallback = MarketSymbolSearchEngine.prepareResults(
                remoteSymbols: cachedResults,
                filter: filter,
                query: normalizedQuery
            )
            if !fallback.isEmpty {
                return Array(fallback.prefix(max(1, outputSize)))
            }
            throw error
        }
    }

    func resolveBulkImportCandidates(
        query: String,
        market: String?,
        outputSize: Int = 30
    ) async throws -> [StockBulkImportCandidate] {
        let normalizedQuery = MarketSymbolSearchEngine.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let cacheKey = makeCacheKey(query: normalizedQuery, filter: .stocks)
        let localResults = MarketSymbolSearchEngine.localResults(filter: .stocks, query: query)
        let remoteResults: [TwelveDataSymbol]
        do {
            let fetched = try await client.searchSymbols(query: query, outputSize: outputSize)
            cachedResultsByKey[cacheKey] = fetched
            remoteResults = fetched
        } catch {
            remoteResults = cachedResultsByKey[cacheKey] ?? []
        }

        let symbols: [TwelveDataSymbol]
        if remoteResults.isEmpty {
            symbols = localResults
        } else {
            symbols = MarketSymbolSearchFormatter.prepareResults(
                remoteResults,
                filter: .stocks,
                query: normalizedQuery
            )
        }
        let candidates = makeBulkImportCandidates(from: symbols)

        return Array(
            MarketInstrumentCandidatePolicy.rankBulkImportCandidates(
                Array(Set(candidates)),
                query: query,
                preferredMarket: market
            )
            .prefix(max(1, outputSize))
        )
    }

    private func makeBulkImportCandidates(from symbols: [TwelveDataSymbol]) -> [StockBulkImportCandidate] {
        symbols.compactMap { symbol -> StockBulkImportCandidate? in
            let type = symbol.normalizedInstrumentType ?? ""
            guard type.contains("stock") || type.contains("equity") || type.contains("etf") || type.isEmpty else {
                return nil
            }

            return StockBulkImportCandidate(
                symbol: symbol.symbol,
                market: symbol.exchange,
                displayName: symbol.displayName,
                currency: symbol.currency ?? "USD",
                providerRaw: "market-backend"
            )
        }
    }

    private func makeCacheKey(query: String, filter: MarketSymbolFilter) -> String {
        "\(filter.cacheKey)|\(query)"
    }
}

private extension MarketSymbolFilter {
    var cacheKey: String {
        switch self {
        case .stocks:
            return "stocks"
        case .crypto:
            return "crypto"
        }
    }
}
