import Foundation

struct MarketSymbolSearchIndexEntry: Sendable {
    let symbol: TwelveDataSymbol
    let filter: MarketSymbolFilter
    let aliases: [String]
    let popularityScore: Int
}

enum MarketSymbolSearchIndex {
    static let entries: [MarketSymbolSearchIndexEntry] = [
        // US mega caps and anchor ETFs kept at the top so quick picks remain stable.
        stock("AAPL", "Apple Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["apple", "apple inc", "iphone maker"], popularityScore: 100),
        stock("MSFT", "Microsoft Corporation", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["microsoft", "windows", "office"], popularityScore: 98),
        stock("NVDA", "NVIDIA Corporation", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["nvidia", "geforce", "ai chips"], popularityScore: 97),
        stock("AMZN", "Amazon.com, Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["amazon", "aws"], popularityScore: 95),
        stock("GOOGL", "Alphabet Inc. Class A", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["google", "alphabet", "youtube"], popularityScore: 96),
        stock("META", "Meta Platforms, Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["meta", "facebook", "instagram"], popularityScore: 93),
        stock("TSLA", "Tesla, Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["tesla", "tesla motors", "elon"], popularityScore: 94),
        etf("SPY", "SPDR S&P 500 ETF Trust", exchange: "NYSE", micCode: "ARCX", aliases: ["sp500", "s&p500", "s&p 500", "snp500", "spyder", "spdr"], popularityScore: 99),
        etf("QQQ", "Invesco QQQ Trust", exchange: "NASDAQ", micCode: "XNAS", aliases: ["nasdaq100", "nasdaq 100", "qqq etf"], popularityScore: 92),
        stock("AMD", "Advanced Micro Devices, Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["amd", "advanced micro devices", "radeon"], popularityScore: 88),
        stock("PLTR", "Palantir Technologies Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["palantir", "pltr"], popularityScore: 84),
        stock("NFLX", "Netflix, Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["netflix", "streaming"], popularityScore: 85),
        etf("GLD", "SPDR Gold Shares", exchange: "NYSE", micCode: "ARCX", aliases: ["gold", "xau", "bullion", "precious metal"], popularityScore: 87),
        stock("AVGO", "Broadcom Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["broadcom", "avgo", "vmware"], popularityScore: 91),
        stock("WMT", "Walmart Inc.", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["walmart", "wal mart", "retail giant"], popularityScore: 89),
        stock("JPM", "JPMorgan Chase & Co.", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["jpmorgan", "jp morgan", "chase"], popularityScore: 86),
        stock("V", "Visa Inc.", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["visa", "payments"], popularityScore: 85),
        stock("LLY", "Eli Lilly and Company", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["eli lilly", "lilly", "pharma"], popularityScore: 84),
        stock("XOM", "Exxon Mobil Corporation", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["exxon", "exxon mobil", "oil major"], popularityScore: 83),
        etf("VOO", "Vanguard S&P 500 ETF", exchange: "NYSE", micCode: "ARCX", aliases: ["voo", "vanguard sp500", "vanguard s&p 500"], popularityScore: 90),
        etf("IVV", "iShares Core S&P 500 ETF", exchange: "NYSE", micCode: "ARCX", aliases: ["ivv", "ishares sp500", "ishares s&p 500"], popularityScore: 82),
        etf("VTI", "Vanguard Total Stock Market ETF", exchange: "NYSE", micCode: "ARCX", aliases: ["vti", "total stock market", "vanguard total market"], popularityScore: 81),
        stock("ORCL", "Oracle Corporation", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["oracle", "database", "cloud database"], popularityScore: 80),
        stock("COST", "Costco Wholesale Corporation", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["costco", "wholesale"], popularityScore: 79),

        // Extra US coverage.
        stock("BRK.B", "Berkshire Hathaway Inc. Class B", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["berkshire", "berkshire hathaway", "buffett"], popularityScore: 78),
        stock("MA", "Mastercard Incorporated", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["mastercard", "payments"], popularityScore: 77),
        stock("BAC", "Bank of America Corporation", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["bank of america", "bofa"], popularityScore: 76),
        stock("KO", "The Coca-Cola Company", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["coca cola", "coke"], popularityScore: 75),
        stock("PEP", "PepsiCo, Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "United States", aliases: ["pepsi", "pepsico"], popularityScore: 74),
        stock("UNH", "UnitedHealth Group Incorporated", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["unitedhealth", "health insurance"], popularityScore: 73),
        stock("HD", "The Home Depot, Inc.", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["home depot"], popularityScore: 72),
        stock("ABBV", "AbbVie Inc.", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["abbvie"], popularityScore: 71),
        stock("MCD", "McDonald's Corporation", exchange: "NYSE", micCode: "XNYS", country: "United States", aliases: ["mcdonalds", "mcd"], popularityScore: 70),
        etf("VXUS", "Vanguard Total International Stock ETF", exchange: "NASDAQ", micCode: "XNAS", aliases: ["vxus", "international stocks", "world ex us"], popularityScore: 69),
        etf("VT", "Vanguard Total World Stock ETF", exchange: "NYSE", micCode: "ARCX", aliases: ["vt", "world stock", "global stocks"], popularityScore: 68),

        // Global ADRs and non-US giants.
        stock("TSM", "Taiwan Semiconductor Manufacturing Company Limited", exchange: "NYSE", micCode: "XNYS", country: "Taiwan", aliases: ["tsm", "tsmc", "taiwan semiconductor", "chips foundry"], popularityScore: 78),
        stock("ASML", "ASML Holding N.V.", exchange: "NASDAQ", micCode: "XNAS", country: "Netherlands", aliases: ["asml", "lithography"], popularityScore: 67),
        stock("NVO", "Novo Nordisk A/S", exchange: "NYSE", micCode: "XNYS", country: "Denmark", aliases: ["novo nordisk", "ozempic"], popularityScore: 66),
        stock("SAP", "SAP SE", exchange: "XETRA", micCode: "XETR", country: "Germany", currency: "EUR", aliases: ["sap", "sap se", "erp"], popularityScore: 65),
        stock("SIE", "Siemens AG", exchange: "XETRA", micCode: "XETR", country: "Germany", currency: "EUR", aliases: ["siemens"], popularityScore: 64),
        stock("MC", "LVMH Moet Hennessy Louis Vuitton SE", exchange: "EPA", micCode: "XPAR", country: "France", currency: "EUR", aliases: ["lvmh", "louis vuitton"], popularityScore: 63),
        stock("RMS", "Hermes International SCA", exchange: "EPA", micCode: "XPAR", country: "France", currency: "EUR", aliases: ["hermes"], popularityScore: 62),
        stock("OR", "L'Oreal S.A.", exchange: "EPA", micCode: "XPAR", country: "France", currency: "EUR", aliases: ["loreal", "l'oreal"], popularityScore: 61),
        stock("NESN", "Nestle S.A.", exchange: "SIX", micCode: "XSWX", country: "Switzerland", currency: "CHF", aliases: ["nestle"], popularityScore: 60),
        stock("NOVN", "Novartis AG", exchange: "SIX", micCode: "XSWX", country: "Switzerland", currency: "CHF", aliases: ["novartis"], popularityScore: 59),
        stock("ROG", "Roche Holding AG", exchange: "SIX", micCode: "XSWX", country: "Switzerland", currency: "CHF", aliases: ["roche"], popularityScore: 58),
        stock("AZN", "AstraZeneca PLC", exchange: "LSE", micCode: "XLON", country: "United Kingdom", currency: "GBP", aliases: ["astrazeneca"], popularityScore: 57),
        stock("HSBA", "HSBC Holdings plc", exchange: "LSE", micCode: "XLON", country: "United Kingdom", currency: "GBP", aliases: ["hsbc"], popularityScore: 56),
        stock("BP", "BP p.l.c.", exchange: "LSE", micCode: "XLON", country: "United Kingdom", currency: "GBP", aliases: ["bp", "british petroleum"], popularityScore: 55),
        stock("RIO", "Rio Tinto plc", exchange: "LSE", micCode: "XLON", country: "United Kingdom", currency: "GBP", aliases: ["rio tinto"], popularityScore: 54),
        stock("SHEL", "Shell plc", exchange: "NYSE", micCode: "XNYS", country: "United Kingdom", aliases: ["shell"], popularityScore: 53),
        stock("BHP", "BHP Group Limited", exchange: "ASX", micCode: "XASX", country: "Australia", currency: "AUD", aliases: ["bhp"], popularityScore: 52),
        stock("CBA", "Commonwealth Bank of Australia", exchange: "ASX", micCode: "XASX", country: "Australia", currency: "AUD", aliases: ["commonwealth bank", "cba"], popularityScore: 51),
        stock("CSL", "CSL Limited", exchange: "ASX", micCode: "XASX", country: "Australia", currency: "AUD", aliases: ["csl"], popularityScore: 50),

        // Japan, Korea, Taiwan.
        stock("7203", "Toyota Motor Corporation", exchange: "TSE", micCode: "XTKS", country: "Japan", currency: "JPY", aliases: ["toyota"], popularityScore: 49),
        stock("6758", "Sony Group Corporation", exchange: "TSE", micCode: "XTKS", country: "Japan", currency: "JPY", aliases: ["sony", "playstation"], popularityScore: 48),
        stock("9984", "SoftBank Group Corp.", exchange: "TSE", micCode: "XTKS", country: "Japan", currency: "JPY", aliases: ["softbank"], popularityScore: 47),
        stock("005930", "Samsung Electronics Co., Ltd.", exchange: "KRX", micCode: "XKRX", country: "South Korea", currency: "KRW", aliases: ["samsung", "samsung electronics"], popularityScore: 46),
        stock("2330", "Taiwan Semiconductor Manufacturing Co. Ltd.", exchange: "TWSE", micCode: "XTAI", country: "Taiwan", currency: "TWD", aliases: ["2330", "tsmc tw", "taiwan semiconductor"], popularityScore: 45),
        stock("2317", "Hon Hai Precision Industry Co., Ltd.", exchange: "TWSE", micCode: "XTAI", country: "Taiwan", currency: "TWD", aliases: ["hon hai", "foxconn"], popularityScore: 44),

        // Greater China and Hong Kong.
        stock("0700", "Tencent Holdings Limited", exchange: "HKEX", micCode: "XHKG", country: "Hong Kong", currency: "HKD", aliases: ["tencent", "wechat"], popularityScore: 43),
        stock("9988", "Alibaba Group Holding Limited", exchange: "HKEX", micCode: "XHKG", country: "Hong Kong", currency: "HKD", aliases: ["alibaba", "baba"], popularityScore: 42),
        stock("3690", "Meituan", exchange: "HKEX", micCode: "XHKG", country: "Hong Kong", currency: "HKD", aliases: ["meituan"], popularityScore: 41),
        stock("1810", "Xiaomi Corporation", exchange: "HKEX", micCode: "XHKG", country: "Hong Kong", currency: "HKD", aliases: ["xiaomi"], popularityScore: 40),
        stock("9618", "JD.com, Inc.", exchange: "HKEX", micCode: "XHKG", country: "Hong Kong", currency: "HKD", aliases: ["jd", "jd com"], popularityScore: 39),
        stock("PDD", "PDD Holdings Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "China", aliases: ["pinduoduo", "pdd"], popularityScore: 38),
        stock("BIDU", "Baidu, Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "China", aliases: ["baidu"], popularityScore: 37),

        // India.
        stock("RELIANCE", "Reliance Industries Limited", exchange: "NSE", micCode: "XNSE", country: "India", currency: "INR", aliases: ["reliance", "ril"], popularityScore: 36),
        stock("TCS", "Tata Consultancy Services Limited", exchange: "NSE", micCode: "XNSE", country: "India", currency: "INR", aliases: ["tcs", "tata consultancy"], popularityScore: 35),
        stock("HDFCBANK", "HDFC Bank Limited", exchange: "NSE", micCode: "XNSE", country: "India", currency: "INR", aliases: ["hdfc bank", "hdfcbank"], popularityScore: 34),
        stock("INFY", "Infosys Limited", exchange: "NSE", micCode: "XNSE", country: "India", currency: "INR", aliases: ["infosys", "infy"], popularityScore: 33),
        stock("ICICIBANK", "ICICI Bank Limited", exchange: "NSE", micCode: "XNSE", country: "India", currency: "INR", aliases: ["icici", "icici bank"], popularityScore: 32),
        stock("BHARTIARTL", "Bharti Airtel Limited", exchange: "NSE", micCode: "XNSE", country: "India", currency: "INR", aliases: ["airtel", "bharti airtel"], popularityScore: 31),

        // Latin America, Middle East, and Eastern Europe.
        stock("MELI", "MercadoLibre, Inc.", exchange: "NASDAQ", micCode: "XNAS", country: "Uruguay", aliases: ["mercadolibre", "meli"], popularityScore: 30),
        stock("PETR4", "Petroleo Brasileiro S.A. Petrobras", exchange: "B3", micCode: "BVMF", country: "Brazil", currency: "BRL", aliases: ["petrobras", "petr4"], popularityScore: 29),
        stock("VALE3", "Vale S.A.", exchange: "B3", micCode: "BVMF", country: "Brazil", currency: "BRL", aliases: ["vale", "vale3"], popularityScore: 28),
        stock("ITUB", "Itau Unibanco Holding S.A.", exchange: "NYSE", micCode: "XNYS", country: "Brazil", aliases: ["itau", "itub"], popularityScore: 27),
        stock("2222", "Saudi Arabian Oil Company", exchange: "TADAWUL", micCode: "XSAU", country: "Saudi Arabia", currency: "SAR", aliases: ["aramco", "saudi aramco"], popularityScore: 26),
        stock("SBER", "Sberbank of Russia PJSC", exchange: "MOEX", micCode: "MISX", country: "Russia", currency: "RUB", aliases: ["sber", "sberbank"], popularityScore: 25),
        stock("GAZP", "Gazprom PJSC", exchange: "MOEX", micCode: "MISX", country: "Russia", currency: "RUB", aliases: ["gazprom", "gazp"], popularityScore: 24),
        stock("LKOH", "PJSC Lukoil", exchange: "MOEX", micCode: "MISX", country: "Russia", currency: "RUB", aliases: ["lukoil", "lkoh"], popularityScore: 23),

        crypto("BTC/USD", "Bitcoin / US Dollar", aliases: ["bitcoin", "btc", "xbt"], popularityScore: 100),
        crypto("ETH/USD", "Ethereum / US Dollar", aliases: ["ethereum", "eth"], popularityScore: 98),
        crypto("SOL/USD", "Solana / US Dollar", aliases: ["solana", "sol"], popularityScore: 91),
        crypto("XRP/USD", "XRP / US Dollar", aliases: ["ripple", "xrp"], popularityScore: 90),
        crypto("ADA/USD", "Cardano / US Dollar", aliases: ["cardano", "ada"], popularityScore: 82),
        crypto("DOGE/USD", "Dogecoin / US Dollar", aliases: ["dogecoin", "doge"], popularityScore: 81),
        crypto("BNB/USD", "BNB / US Dollar", aliases: ["bnb", "binance coin", "binance"], popularityScore: 83),
        crypto("AVAX/USD", "Avalanche / US Dollar", aliases: ["avax", "avalanche"], popularityScore: 79),
        crypto("DOT/USD", "Polkadot / US Dollar", aliases: ["dot", "polkadot"], popularityScore: 78),
        crypto("LINK/USD", "Chainlink / US Dollar", aliases: ["link", "chainlink"], popularityScore: 77)
    ]

    private static func stock(
        _ symbol: String,
        _ name: String,
        exchange: String,
        micCode: String?,
        country: String?,
        currency: String = "USD",
        aliases: [String],
        popularityScore: Int
    ) -> MarketSymbolSearchIndexEntry {
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(
                symbol: symbol,
                instrumentName: name,
                exchange: exchange,
                micCode: micCode,
                instrumentType: "Common Stock",
                country: country,
                currency: currency
            ),
            filter: .stocks,
            aliases: aliases,
            popularityScore: popularityScore
        )
    }

    private static func etf(
        _ symbol: String,
        _ name: String,
        exchange: String,
        micCode: String?,
        aliases: [String],
        popularityScore: Int
    ) -> MarketSymbolSearchIndexEntry {
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(
                symbol: symbol,
                instrumentName: name,
                exchange: exchange,
                micCode: micCode,
                instrumentType: "ETF",
                country: "United States",
                currency: "USD"
            ),
            filter: .stocks,
            aliases: aliases,
            popularityScore: popularityScore
        )
    }

    private static func crypto(
        _ symbol: String,
        _ name: String,
        aliases: [String],
        popularityScore: Int
    ) -> MarketSymbolSearchIndexEntry {
        MarketSymbolSearchIndexEntry(
            symbol: TwelveDataSymbol(
                symbol: symbol,
                instrumentName: name,
                exchange: "CRYPTO",
                micCode: nil,
                instrumentType: "Cryptocurrency",
                country: nil,
                currency: "USD"
            ),
            filter: .crypto,
            aliases: aliases,
            popularityScore: popularityScore
        )
    }

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

        if normalize(first.symbol) == normalizedQuery {
            return false
        }

        return hasExactLocalMatch(symbol: first, filter: filter, query: normalizedQuery)
    }

    static func prioritizeProviderSuffixMatches(
        _ symbols: [TwelveDataSymbol],
        query: String
    ) -> [TwelveDataSymbol] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return symbols }

        var preferred: [TwelveDataSymbol] = []
        var rest: [TwelveDataSymbol] = []

        for symbol in symbols {
            let canonicalTicker = StockBulkImportCandidate.canonicalTicker(from: symbol.symbol)
            let hasSuffix = symbol.symbol.contains(".") || symbol.symbol.contains(":")
            if hasSuffix && normalize(canonicalTicker) == normalizedQuery {
                preferred.append(symbol)
            } else {
                rest.append(symbol)
            }
        }

        return preferred + rest
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
