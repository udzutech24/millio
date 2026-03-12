import Foundation

struct MarketSymbolSearchIndexEntry: Sendable {
    let symbol: TwelveDataSymbol
    let filter: MarketSymbolFilter
    let aliases: [String]
    let popularityScore: Int
}

enum MarketSymbolSearchIndex {
    static let entries: [MarketSymbolSearchIndexEntry] = [
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "AAPL", instrumentName: "Apple Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["apple", "apple inc", "iphone maker"],
            popularityScore: 100
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "MSFT", instrumentName: "Microsoft Corporation", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["microsoft", "windows", "office"],
            popularityScore: 98
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "NVDA", instrumentName: "NVIDIA Corporation", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["nvidia", "geforce", "ai chips"],
            popularityScore: 97
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "AMZN", instrumentName: "Amazon.com, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["amazon", "aws"],
            popularityScore: 95
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "GOOGL", instrumentName: "Alphabet Inc. Class A", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["google", "alphabet", "youtube"],
            popularityScore: 96
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "META", instrumentName: "Meta Platforms, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["meta", "facebook", "instagram"],
            popularityScore: 93
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "TSLA", instrumentName: "Tesla, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["tesla", "tesla motors", "elon"],
            popularityScore: 94
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "SPY", instrumentName: "SPDR S&P 500 ETF Trust", exchange: "NYSE", micCode: "ARCX", instrumentType: "ETF", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["sp500", "s&p500", "s&p 500", "snp500", "spyder", "spdr"],
            popularityScore: 99
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "QQQ", instrumentName: "Invesco QQQ Trust", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["nasdaq100", "nasdaq 100", "qqq etf"],
            popularityScore: 92
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "AMD", instrumentName: "Advanced Micro Devices, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["amd", "advanced micro devices", "radeon"],
            popularityScore: 88
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "PLTR", instrumentName: "Palantir Technologies Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["palantir", "pltr"],
            popularityScore: 84
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "NFLX", instrumentName: "Netflix, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["netflix", "streaming"],
            popularityScore: 85
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "GLD", instrumentName: "SPDR Gold Shares", exchange: "NYSE", micCode: "ARCX", instrumentType: "ETF", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["gold", "xau", "bullion", "precious metal"],
            popularityScore: 87
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "AVGO", instrumentName: "Broadcom Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["broadcom", "avgo", "vmware"],
            popularityScore: 91
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "WMT", instrumentName: "Walmart Inc.", exchange: "NYSE", micCode: "XNYS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["walmart", "wal mart", "retail giant"],
            popularityScore: 89
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "JPM", instrumentName: "JPMorgan Chase & Co.", exchange: "NYSE", micCode: "XNYS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["jpmorgan", "jp morgan", "chase"],
            popularityScore: 86
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "V", instrumentName: "Visa Inc.", exchange: "NYSE", micCode: "XNYS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["visa", "payments"],
            popularityScore: 85
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "LLY", instrumentName: "Eli Lilly and Company", exchange: "NYSE", micCode: "XNYS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["eli lilly", "lilly", "pharma"],
            popularityScore: 84
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "XOM", instrumentName: "Exxon Mobil Corporation", exchange: "NYSE", micCode: "XNYS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["exxon", "exxon mobil", "oil major"],
            popularityScore: 83
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "VOO", instrumentName: "Vanguard S&P 500 ETF", exchange: "NYSE", micCode: "ARCX", instrumentType: "ETF", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["voo", "vanguard sp500", "vanguard s&p 500"],
            popularityScore: 90
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "IVV", instrumentName: "iShares Core S&P 500 ETF", exchange: "NYSE", micCode: "ARCX", instrumentType: "ETF", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["ivv", "ishares sp500", "ishares s&p 500"],
            popularityScore: 82
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "VTI", instrumentName: "Vanguard Total Stock Market ETF", exchange: "NYSE", micCode: "ARCX", instrumentType: "ETF", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["vti", "total stock market", "vanguard total market"],
            popularityScore: 81
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "ORCL", instrumentName: "Oracle Corporation", exchange: "NYSE", micCode: "XNYS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["oracle", "database", "cloud database"],
            popularityScore: 80
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "COST", instrumentName: "Costco Wholesale Corporation", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
            filter: .stocks,
            aliases: ["costco", "wholesale"],
            popularityScore: 79
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "TSM", instrumentName: "Taiwan Semiconductor Manufacturing Company Limited", exchange: "NYSE", micCode: "XNYS", instrumentType: "Common Stock", country: "Taiwan", currency: "USD"),
            filter: .stocks,
            aliases: ["tsm", "tsmc", "taiwan semiconductor", "chips foundry"],
            popularityScore: 78
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "BTC/USD", instrumentName: "Bitcoin / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["bitcoin", "btc", "xbt"],
            popularityScore: 100
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "ETH/USD", instrumentName: "Ethereum / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["ethereum", "eth"],
            popularityScore: 98
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "SOL/USD", instrumentName: "Solana / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["solana", "sol"],
            popularityScore: 91
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "XRP/USD", instrumentName: "XRP / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["ripple", "xrp"],
            popularityScore: 90
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "ADA/USD", instrumentName: "Cardano / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["cardano", "ada"],
            popularityScore: 82
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "DOGE/USD", instrumentName: "Dogecoin / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["dogecoin", "doge"],
            popularityScore: 81
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "BNB/USD", instrumentName: "BNB / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["bnb", "binance coin", "binance"],
            popularityScore: 83
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "AVAX/USD", instrumentName: "Avalanche / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["avax", "avalanche"],
            popularityScore: 79
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "DOT/USD", instrumentName: "Polkadot / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["dot", "polkadot"],
            popularityScore: 78
        ),
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(symbol: "LINK/USD", instrumentName: "Chainlink / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
            filter: .crypto,
            aliases: ["link", "chainlink"],
            popularityScore: 77
        )
    ]

    static func topSymbols(for filter: MarketSymbolFilter, limit: Int) -> [TwelveDataSymbol] {
        entries
            .filter { $0.filter == filter }
            .sorted { lhs, rhs in
                if lhs.popularityScore != rhs.popularityScore {
                    return lhs.popularityScore > rhs.popularityScore
                }

                return lhs.symbol.displayName.localizedCaseInsensitiveCompare(rhs.symbol.displayName) == .orderedAscending
            }
            .prefix(limit)
            .map(\.symbol)
    }
}

enum MarketSymbolSearchEngine {
    static let minimumRemoteQueryLength = 2
    static let remoteSearchDebounceMilliseconds: UInt64 = 500

    static func prepareResults(
        remoteSymbols: [TwelveDataSymbol],
        filter: MarketSymbolFilter,
        query: String
    ) -> [TwelveDataSymbol] {
        let normalizedQuery = normalize(query)
        let localMatches = localResults(filter: filter, query: query)
        let merged = MarketSymbolSearchFormatter.deduplicated((localMatches + remoteSymbols).filter { filter.matches($0) })

        return merged.sorted { lhs, rhs in
            let lhsScore = rankingScore(for: lhs, filter: filter, query: normalizedQuery)
            let rhsScore = rankingScore(for: rhs, filter: filter, query: normalizedQuery)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            return MarketSymbolSearchFormatter.compareStable(lhs, rhs, query: normalizedQuery)
        }
    }

    static func localResults(filter: MarketSymbolFilter, query: String) -> [TwelveDataSymbol] {
        let query = normalize(query)
        guard !query.isEmpty else { return [] }

        return MarketSymbolSearchIndex.entries
            .filter { $0.filter == filter }
            .filter { entry in
                searchableTokens(for: entry.symbol, aliases: entry.aliases).contains { token in
                    token == query || token.hasPrefix(query) || token.contains(query)
                }
            }
            .sorted { lhs, rhs in
                let lhsScore = localRankingScore(entry: lhs, query: query)
                let rhsScore = localRankingScore(entry: rhs, query: query)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.symbol.displayName.localizedCaseInsensitiveCompare(rhs.symbol.displayName) == .orderedAscending
            }
            .map(\.symbol)
    }

    static func shouldSkipRemoteSearch(filter: MarketSymbolFilter, query: String, localResults: [TwelveDataSymbol]) -> Bool {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return true }
        guard normalizedQuery.count >= minimumRemoteQueryLength else { return true }
        guard let first = localResults.first else { return false }

        return hasExactLocalMatch(symbol: first, filter: filter, query: normalizedQuery)
    }

    private static func rankingScore(
        for symbol: TwelveDataSymbol,
        filter: MarketSymbolFilter,
        query: String
    ) -> Int {
        let normalizedSymbol = normalize(symbol.symbol)
        let normalizedName = normalize(symbol.displayName)
        let normalizedExchange = normalize(symbol.exchange ?? "")
        let aliases = normalizedAliases(for: symbol, filter: filter)

        var score = 0

        if normalizedSymbol == query { score += 10_000 }
        else if aliases.contains(query) { score += 9_700 }
        else if normalizedName == query { score += 9_400 }
        else if normalizedSymbol.hasPrefix(query) { score += 8_800 }
        else if aliases.contains(where: { $0.hasPrefix(query) }) { score += 8_500 }
        else if normalizedName.hasPrefix(query) { score += 8_100 }
        else if normalizedSymbol.contains(query) { score += 7_600 }
        else if aliases.contains(where: { $0.contains(query) }) { score += 7_300 }
        else if normalizedName.contains(query) { score += 7_000 }

        score += popularityScore(for: symbol, filter: filter) * 10

        switch filter {
        case .stocks:
            if ["NASDAQ", "NYSE", "AMEX"].contains(normalizedExchange) { score += 120 }
        case .crypto:
            if normalizedExchange == "CRYPTO" { score += 120 }
        }

        if let instrumentType = symbol.normalizedInstrumentType {
            switch filter {
            case .stocks where instrumentType.contains("stock"):
                score += 60
            case .crypto where instrumentType.contains("crypto"):
                score += 60
            default:
                break
            }
        }

        return score
    }

    private static func localRankingScore(entry: MarketSymbolSearchIndexEntry, query: String) -> Int {
        let symbol = normalize(entry.symbol.symbol)
        let name = normalize(entry.symbol.displayName)
        let aliases = entry.aliases.map(normalize)

        var score = 0
        if symbol == query { score += 10_000 }
        else if aliases.contains(query) { score += 9_700 }
        else if name == query { score += 9_400 }
        else if symbol.hasPrefix(query) { score += 8_800 }
        else if aliases.contains(where: { $0.hasPrefix(query) }) { score += 8_500 }
        else if name.hasPrefix(query) { score += 8_100 }
        else if symbol.contains(query) { score += 7_600 }
        else if aliases.contains(where: { $0.contains(query) }) { score += 7_300 }
        else if name.contains(query) { score += 7_000 }

        return score + (entry.popularityScore * 10)
    }

    private static func hasExactLocalMatch(symbol: TwelveDataSymbol, filter: MarketSymbolFilter, query: String) -> Bool {
        let normalizedSymbol = normalize(symbol.symbol)
        let normalizedName = normalize(symbol.displayName)
        let aliases = normalizedAliases(for: symbol, filter: filter)

        return normalizedSymbol == query || normalizedName == query || aliases.contains(query)
    }

    private static func popularityScore(for symbol: TwelveDataSymbol, filter: MarketSymbolFilter) -> Int {
        MarketSymbolSearchIndex.entries.first {
            $0.filter == filter && MarketSymbolSearchFormatter.dedupeIdentityKey(for: $0.symbol) == MarketSymbolSearchFormatter.dedupeIdentityKey(for: symbol)
        }?.popularityScore ?? 0
    }

    private static func normalizedAliases(for symbol: TwelveDataSymbol, filter: MarketSymbolFilter) -> [String] {
        MarketSymbolSearchIndex.entries.first {
            $0.filter == filter && MarketSymbolSearchFormatter.dedupeIdentityKey(for: $0.symbol) == MarketSymbolSearchFormatter.dedupeIdentityKey(for: symbol)
        }?.aliases.map(normalize) ?? []
    }

    private static func searchableTokens(for symbol: TwelveDataSymbol, aliases: [String]) -> [String] {
        var tokens = [
            symbol.symbol,
            symbol.displayName,
            symbol.exchange ?? "",
            symbol.country ?? "",
            symbol.currency ?? ""
        ] + aliases

        // Common slash-free representation for pairs like BTC/USD.
        tokens.append(symbol.symbol.replacingOccurrences(of: "/", with: ""))
        tokens.append(symbol.symbol.replacingOccurrences(of: "/", with: " "))

        return tokens
            .map(normalize)
            .filter { !$0.isEmpty }
    }

    static func normalize(_ value: String) -> String {
        let uppercased = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()

        let cleaned = uppercased.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }
        .joined()

        return cleaned
            .split(whereSeparator: \.isWhitespace)
            .joined()
    }
}
