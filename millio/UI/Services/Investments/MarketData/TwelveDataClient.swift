import Foundation

enum MarketInstrumentIdentity {
    static func canonicalQuoteLookupKey(symbol: String, exchange: String?) -> String {
        let ticker = canonicalTicker(from: symbol)
        guard !ticker.isEmpty else { return "" }

        switch normalizedMarket(exchange: exchange, symbol: symbol) {
        case "US":
            return "\(ticker).US"
        case "NASDAQ", "NYSE", "AMEX", "BATS", "IEX":
            return ticker
        case let market?:
            return "\(market):\(ticker)"
        case nil:
            return ticker
        }
    }

    static func fallbackQuoteLookupKeys(symbol: String, exchange: String?) -> [String] {
        let ticker = canonicalTicker(from: symbol)
        guard !ticker.isEmpty else { return [] }

        switch normalizedMarket(exchange: exchange, symbol: symbol) {
        case "US":
            return unique([
                "\(ticker).US",
                ticker,
                "US:\(ticker)"
            ])
        case "NASDAQ", "NYSE", "AMEX", "BATS", "IEX":
            let market = normalizedMarket(exchange: exchange, symbol: symbol) ?? ""
            return unique([
                ticker,
                "\(ticker).US",
                "\(market):\(ticker)"
            ])
        case let market?:
            return unique([
                "\(market):\(ticker)",
                ticker
            ])
        case nil:
            return unique([ticker])
        }
    }

    private static func canonicalTicker(from rawSymbol: String) -> String {
        let trimmed = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return "" }

        if trimmed.contains(":"),
           let last = trimmed.split(separator: ":", maxSplits: 1).last {
            return String(last)
        }

        if trimmed.contains("."),
           let first = trimmed.split(separator: ".", maxSplits: 1).first {
            return String(first)
        }

        return trimmed
    }

    private static func normalizedMarket(exchange: String?, symbol: String) -> String? {
        if let exchange = exchange?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
           !exchange.isEmpty {
            return exchange
        }

        let rawSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if rawSymbol.contains(":"),
           let market = rawSymbol.split(separator: ":", maxSplits: 1).first {
            let normalized = String(market).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return normalized.isEmpty ? nil : normalized
        }

        if rawSymbol.hasSuffix(".US") {
            return "US"
        }

        return nil
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { return false }
            return seen.insert(normalized).inserted
        }
    }
}

protocol MarketDataClientProtocol: Sendable {
    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol]
    func latestQuote(symbol: String, forceRefresh: Bool) async throws -> AssetSummary?
    /// Пакетная загрузка котировок (до 8 символов за запрос). Результаты кэшируются.
    func fetchQuotes(symbols: [String]) async throws -> [AssetSummary]
}

extension MarketDataClientProtocol {
    func searchSymbols(query: String) async throws -> [TwelveDataSymbol] {
        try await searchSymbols(query: query, outputSize: 20)
    }

    func latestPrice(symbol: String, forceRefresh: Bool) async throws -> Double? {
        try await latestQuote(symbol: symbol, forceRefresh: forceRefresh)?.price
    }
}

struct TwelveDataSymbol: Codable, Identifiable, Equatable, Sendable {
    let symbol: String
    let instrumentName: String?
    let exchange: String?
    let micCode: String?
    let instrumentType: String?
    let country: String?
    let currency: String?

    var id: String { symbol }

    var normalizedInstrumentType: String? {
        instrumentType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var displayName: String {
        let trimmed = instrumentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? symbol : trimmed
    }

    var canonicalQuoteLookupKey: String {
        MarketInstrumentIdentity.canonicalQuoteLookupKey(symbol: symbol, exchange: exchange)
    }

    init(
        symbol: String,
        instrumentName: String?,
        exchange: String?,
        micCode: String?,
        instrumentType: String?,
        country: String?,
        currency: String?
    ) {
        self.symbol = symbol
        self.instrumentName = instrumentName
        self.exchange = exchange
        self.micCode = micCode
        self.instrumentType = instrumentType
        self.country = country
        self.currency = currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        symbol = try container.decode(String.self, forKey: DynamicCodingKey("symbol"))
        instrumentName = try container.decodeIfPresent(String.self, forKeys: ["name", "instrument_name"])
        exchange = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("exchange"))
        micCode = try container.decodeIfPresent(String.self, forKeys: ["micCode", "mic_code"])
        instrumentType = try container.decodeIfPresent(String.self, forKeys: ["instrumentType", "instrument_type"])
        country = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("country"))
        currency = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("currency"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(symbol, forKey: DynamicCodingKey("symbol"))
        try container.encodeIfPresent(instrumentName, forKey: DynamicCodingKey("name"))
        try container.encodeIfPresent(exchange, forKey: DynamicCodingKey("exchange"))
        try container.encodeIfPresent(micCode, forKey: DynamicCodingKey("micCode"))
        try container.encodeIfPresent(instrumentType, forKey: DynamicCodingKey("instrumentType"))
        try container.encodeIfPresent(country, forKey: DynamicCodingKey("country"))
        try container.encodeIfPresent(currency, forKey: DynamicCodingKey("currency"))
    }
}

struct MarketSearchResult: Codable, Equatable, Sendable {
    let symbol: String
    let name: String?
    let exchange: String?
    let micCode: String?
    let currency: String?
    let country: String?
    let instrumentType: String?

    var asSymbol: TwelveDataSymbol {
        TwelveDataSymbol(
            symbol: symbol,
            instrumentName: name,
            exchange: exchange,
            micCode: micCode,
            instrumentType: instrumentType,
            country: country,
            currency: currency
        )
    }
}

enum MarketQuoteResolutionStatus: String, Codable, Equatable, Sendable {
    case fresh
    case stale
    case notFound = "not_found"
    case providerError = "provider_error"
}

struct AssetSummary: Codable, Equatable, Sendable {
    let symbol: String
    let canonicalSymbol: String?
    let providerSymbol: String?
    let name: String?
    let exchange: String?
    let micCode: String?
    let currency: String?
    let price: Double?
    let previousClose: Double?
    let change: Double?
    let percentChange: Double?
    let isMarketOpen: Bool?
    let resolutionStatus: MarketQuoteResolutionStatus
    let updatedAt: String
    let isStale: Bool

    var updatedAtDate: Date? {
        MarketAPIClient.date(from: updatedAt)
    }

    var canonicalQuoteLookupKey: String {
        if let canonicalSymbol = canonicalSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
           !canonicalSymbol.isEmpty {
            return canonicalSymbol
        }

        return MarketInstrumentIdentity.canonicalQuoteLookupKey(symbol: symbol, exchange: exchange)
    }

    var quoteLookupKeys: [String] {
        var candidates: [String] = [
            symbol,
            canonicalQuoteLookupKey
        ]

        if let canonicalSymbol,
           !canonicalSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(canonicalSymbol)
            candidates.append(
                contentsOf: MarketInstrumentIdentity.fallbackQuoteLookupKeys(
                    symbol: canonicalSymbol,
                    exchange: exchange
                )
            )
        }

        if let providerSymbol,
           !providerSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(providerSymbol)
            candidates.append(
                contentsOf: MarketInstrumentIdentity.fallbackQuoteLookupKeys(
                    symbol: providerSymbol,
                    exchange: exchange
                )
            )
        }

        candidates.append(
            contentsOf: MarketInstrumentIdentity.fallbackQuoteLookupKeys(
                symbol: symbol,
                exchange: exchange
            )
        )

        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
}

struct ChartPoint: Codable, Equatable, Sendable {
    let datetime: String
    let open: Double?
    let high: Double?
    let low: Double?
    let close: Double?
    let volume: Double?
}

struct ChartResponse: Codable, Equatable, Sendable {
    let symbol: String
    let interval: String
    let currency: String?
    let points: [ChartPoint]
    let updatedAt: String
    let isStale: Bool

    var updatedAtDate: Date? {
        MarketAPIClient.date(from: updatedAt)
    }
}

struct AssetDetailsSnapshot: Codable, Equatable, Sendable {
    let symbol: String
    let selectedInterval: String
    let summary: AssetSummary
    let chart: ChartResponse
    let hasStaleData: Bool
    let updatedAt: String
}

struct WatchlistResponse: Codable, Equatable, Sendable {
    let items: [AssetSummary]
}

struct WatchlistItemMetadata: Codable, Equatable, Sendable {
    let id: String
    let symbol: String
    let createdAt: String
}

struct WatchlistSnapshotItem: Codable, Equatable, Sendable {
    let watchlistItem: WatchlistItemMetadata
    let market: AssetSummary
}

struct WatchlistSnapshot: Codable, Equatable, Sendable {
    let items: [WatchlistSnapshotItem]
    let total: Int
    let isEmpty: Bool
    let hasStaleItems: Bool
    let updatedAt: String
}

struct WatchlistMutationResponse: Codable, Equatable, Sendable {
    let success: Bool
    let item: WatchlistItemMetadata?
}

struct AddToWatchlistRequest: Encodable, Sendable {
    let symbol: String
}

enum MarketAPIClientError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case unconfigured
    case unauthorized(requestId: String? = nil)
    case backend(statusCode: Int, message: String, requestId: String? = nil)
    case transport(String)
    case decodingFailed(requestId: String? = nil)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Backend API base URL configuration is missing or invalid."
        case .unconfigured:
            return "Market API client is not configured yet."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .backend(_, let message, _):
            return message
        case .transport(let message):
            return message
        case .decodingFailed:
            return String(localized: "finances.market.error_generic")
        }
    }

    var requestId: String? {
        switch self {
        case .unauthorized(let requestId),
             .backend(_, _, let requestId),
             .decodingFailed(let requestId):
            return requestId
        case .invalidConfiguration,
             .unconfigured,
             .transport:
            return nil
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: [String]) throws -> T? {
        for rawKey in keys {
            let key = DynamicCodingKey(rawKey)
            if contains(key) {
                return try decodeIfPresent(type, forKey: key)
            }
        }
        return nil
    }
}

actor MarketQuoteCacheStore {
    private struct CacheEntry<Value: Sendable>: Sendable {
        let createdAt: Date
        let value: Value
    }

    private let ttl: TimeInterval
    private var searchCache: [String: CacheEntry<[TwelveDataSymbol]>] = [:]
    private var quoteCache: [String: CacheEntry<AssetSummary>] = [:]
    private var assetSummaryCache: [String: CacheEntry<AssetSummary>] = [:]
    private var assetDetailsCache: [String: CacheEntry<AssetDetailsSnapshot>] = [:]
    private var watchlistCache: CacheEntry<WatchlistResponse>?
    private var watchlistSnapshotCache: CacheEntry<WatchlistSnapshot>?

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func search(for key: String) -> [TwelveDataSymbol]? {
        guard let entry = searchCache[key], Date().timeIntervalSince(entry.createdAt) < ttl else {
            searchCache[key] = nil
            return nil
        }
        return entry.value
    }

    func setSearch(_ value: [TwelveDataSymbol], for key: String) {
        searchCache[key] = CacheEntry(createdAt: Date(), value: value)
    }

    func quote(for key: String) -> AssetSummary? {
        guard let entry = quoteCache[key], Date().timeIntervalSince(entry.createdAt) < ttl else {
            quoteCache[key] = nil
            return nil
        }
        return entry.value
    }

    func setQuote(_ value: AssetSummary, for key: String) {
        quoteCache[key] = CacheEntry(createdAt: Date(), value: value)
    }

    func assetSummary(for key: String) -> AssetSummary? {
        guard let entry = assetSummaryCache[key], Date().timeIntervalSince(entry.createdAt) < ttl else {
            assetSummaryCache[key] = nil
            return nil
        }
        return entry.value
    }

    func setAssetSummary(_ value: AssetSummary, for key: String) {
        assetSummaryCache[key] = CacheEntry(createdAt: Date(), value: value)
    }

    func assetDetails(for key: String) -> AssetDetailsSnapshot? {
        guard let entry = assetDetailsCache[key], Date().timeIntervalSince(entry.createdAt) < ttl else {
            assetDetailsCache[key] = nil
            return nil
        }
        return entry.value
    }

    func setAssetDetails(_ value: AssetDetailsSnapshot, for key: String) {
        assetDetailsCache[key] = CacheEntry(createdAt: Date(), value: value)
    }

    func watchlist() -> WatchlistResponse? {
        guard let watchlistCache, Date().timeIntervalSince(watchlistCache.createdAt) < ttl else {
            self.watchlistCache = nil
            return nil
        }
        return watchlistCache.value
    }

    func setWatchlist(_ value: WatchlistResponse) {
        watchlistCache = CacheEntry(createdAt: Date(), value: value)
    }

    func watchlistSnapshot() -> WatchlistSnapshot? {
        guard let watchlistSnapshotCache, Date().timeIntervalSince(watchlistSnapshotCache.createdAt) < ttl else {
            self.watchlistSnapshotCache = nil
            return nil
        }
        return watchlistSnapshotCache.value
    }

    func setWatchlistSnapshot(_ value: WatchlistSnapshot) {
        watchlistSnapshotCache = CacheEntry(createdAt: Date(), value: value)
    }
}

private actor MarketAPIAuthContext {
    private var authService: (any AuthServiceProtocol)?

    func configure(authService: any AuthServiceProtocol) {
        self.authService = authService
    }

    func resolve() -> (any AuthServiceProtocol)? {
        authService
    }
}

private actor MarketAPIConfigurationContext {
    private var configurationProvider: @Sendable () throws -> AuthConfiguration = { try AuthConfiguration.live() }

    func configure(provider: @escaping @Sendable () throws -> AuthConfiguration) {
        configurationProvider = provider
    }

    func resolve() throws -> AuthConfiguration {
        try configurationProvider()
    }
}

final class MarketAPIClient: MarketDataClientProtocol, @unchecked Sendable {
    static let shared = MarketAPIClient()

    fileprivate static let iso8601Formatter = ISO8601DateFormatter()

    private struct ErrorEnvelope: Decodable {
        let message: MessageValue?
        let error: String?

        enum MessageValue: Decodable {
            case string(String)
            case array([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(String.self) {
                    self = .string(value)
                    return
                }
                if let value = try? container.decode([String].self) {
                    self = .array(value)
                    return
                }
                throw DecodingError.typeMismatch(
                    MessageValue.self,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported market error format")
                )
            }
        }

        var resolvedMessage: String {
            switch message {
            case .string(let value):
                return value
            case .array(let values):
                return values.joined(separator: ", ")
            case nil:
                return error ?? String(localized: "finances.market.error_generic")
            }
        }
    }

    private let session: URLSession
    private let cacheStore: MarketQuoteCacheStore
    private let authContext = MarketAPIAuthContext()
    private let configurationContext = MarketAPIConfigurationContext()
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        session: URLSession = .shared,
        cacheTTL: TimeInterval = 30
    ) {
        self.session = session
        self.cacheStore = MarketQuoteCacheStore(ttl: cacheTTL)
        decoder = JSONDecoder()
        encoder = JSONEncoder()

        Self.iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func configure(
        authService: any AuthServiceProtocol,
        configurationProvider: @escaping @Sendable () throws -> AuthConfiguration
    ) async {
        await authContext.configure(authService: authService)
        await configurationContext.configure(provider: configurationProvider)
    }

    func searchSymbols(query: String, outputSize: Int = 20) async throws -> [TwelveDataSymbol] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalizedQuery.isEmpty else {
            return []
        }

        if let cached = await cacheStore.search(for: normalizedQuery) {
            return Array(cached.prefix(max(1, outputSize)))
        }

        let results: [MarketSearchResult] = try await authorizedRequest(
            path: "market/search",
            method: "GET",
            queryItems: [URLQueryItem(name: "q", value: normalizedQuery)]
        )

        let mapped = results.map(\.asSymbol)
        await cacheStore.setSearch(mapped, for: normalizedQuery)
        return Array(mapped.prefix(max(1, outputSize)))
    }

    func latestQuote(symbol: String, forceRefresh: Bool = false) async throws -> AssetSummary? {
        let normalizedSymbol = normalizedSymbol(symbol)
        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        if !forceRefresh, let cached = await cacheStore.quote(for: normalizedSymbol) {
            return cached
        }

        let quotes = try await fetchQuotes(symbols: [normalizedSymbol])
        let quote = quotes.first
        if let quote {
            await cacheStore.setQuote(quote, for: normalizedSymbol)
        }
        return quote
    }

    func fetchQuotes(symbols: [String]) async throws -> [AssetSummary] {
        let normalizedSymbols = symbols
            .map(normalizedSymbol)
            .filter { !$0.isEmpty }

        guard !normalizedSymbols.isEmpty else {
            return []
        }

        // Backend now owns tracked symbol refresh, so we reuse fresh client cache entries
        // and only ask for symbols that are currently missing from the local cache.
        var quotesByRequestedSymbol: [String: AssetSummary] = [:]
        var missingSymbols: [String] = []

        for symbol in normalizedSymbols {
            if let cached = await cacheStore.quote(for: symbol) {
                quotesByRequestedSymbol[symbol] = cached
            } else {
                missingSymbols.append(symbol)
            }
        }

        if !missingSymbols.isEmpty {
            let fetchedQuotes: [AssetSummary] = try await authorizedRequest(
                path: "market/quotes",
                method: "GET",
                queryItems: [URLQueryItem(name: "symbols", value: missingSymbols.joined(separator: ","))]
            )

            for quote in fetchedQuotes {
                for key in quote.quoteLookupKeys {
                    await cacheStore.setQuote(quote, for: key)
                    if missingSymbols.contains(key) {
                        quotesByRequestedSymbol[key] = quote
                    }
                }
            }
        }

        return normalizedSymbols.compactMap { quotesByRequestedSymbol[$0] }
    }

    func assetSummary(symbol: String) async throws -> AssetSummary {
        let symbolKey = normalizedSymbol(symbol)
        if let cached = await cacheStore.assetSummary(for: symbolKey) {
            return cached
        }

        let response: AssetSummary = try await authorizedRequest(
            path: "market/assets/\(encodedPathComponent(symbolKey))/summary",
            method: "GET"
        )
        await cacheStore.setAssetSummary(response, for: symbolKey)
        return response
    }

    func assetChart(symbol: String, interval: String = "1day", outputSize: Int = 30) async throws -> ChartResponse {
        try await authorizedRequest(
            path: "market/assets/\(encodedPathComponent(normalizedSymbol(symbol)))/chart",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "interval", value: interval),
                URLQueryItem(name: "outputsize", value: String(outputSize))
            ]
        )
    }

    func assetDetails(symbol: String, interval: String = "1day") async throws -> AssetDetailsSnapshot {
        let symbolKey = normalizedSymbol(symbol)
        let cacheKey = "\(symbolKey)|\(interval)"
        if let cached = await cacheStore.assetDetails(for: cacheKey) {
            return cached
        }

        let response: AssetDetailsSnapshot = try await authorizedRequest(
            path: "market/assets/\(encodedPathComponent(symbolKey))/details",
            method: "GET",
            queryItems: [URLQueryItem(name: "interval", value: interval)]
        )
        await cacheStore.setAssetDetails(response, for: cacheKey)
        return response
    }

    func watchlist() async throws -> WatchlistResponse {
        if let cached = await cacheStore.watchlist() {
            return cached
        }

        let response: WatchlistResponse = try await authorizedRequest(path: "market/watchlist", method: "GET")
        await cacheStore.setWatchlist(response)
        return response
    }

    func watchlistSnapshot() async throws -> WatchlistSnapshot {
        if let cached = await cacheStore.watchlistSnapshot() {
            return cached
        }

        let response: WatchlistSnapshot = try await authorizedRequest(path: "market/watchlist/snapshot", method: "GET")
        await cacheStore.setWatchlistSnapshot(response)
        return response
    }

    func addToWatchlist(symbol: String) async throws -> WatchlistMutationResponse {
        try await authorizedRequest(
            path: "market/watchlist",
            method: "POST",
            body: AddToWatchlistRequest(symbol: normalizedSymbol(symbol))
        )
    }

    func removeFromWatchlist(symbol: String) async throws -> WatchlistMutationResponse {
        try await authorizedRequest(
            path: "market/watchlist/\(encodedPathComponent(normalizedSymbol(symbol)))",
            method: "DELETE"
        )
    }

    fileprivate static func date(from value: String) -> Date? {
        iso8601Formatter.date(from: value) ?? {
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            return fallback.date(from: value)
        }()
    }

    private func authorizedRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body? = nil
    ) async throws -> Response {
        let authService = try await resolvedAuthService()
        do {
            let accessToken = try await authService.accessToken(forceRefresh: false)
            return try await request(
                path: path,
                method: method,
                accessToken: accessToken,
                queryItems: queryItems,
                body: body
            )
        } catch MarketAPIClientError.unauthorized {
            let refreshedToken = try await authService.accessToken(forceRefresh: true)
            return try await request(
                path: path,
                method: method,
                accessToken: refreshedToken,
                queryItems: queryItems,
                body: body
            )
        }
    }

    private func authorizedRequest<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await authorizedRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            body: Optional<String>.none
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        accessToken: String,
        queryItems: [URLQueryItem],
        body: Body?
    ) async throws -> Response {
        let configuration: AuthConfiguration
        do {
            configuration = try await configurationContext.resolve()
        } catch {
            throw MarketAPIClientError.invalidConfiguration
        }

        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw MarketAPIClientError.invalidConfiguration
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        components.path += normalizedPath
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw MarketAPIClientError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MarketAPIClientError.transport("Invalid market response.")
            }

            let requestId = httpResponse.value(forHTTPHeaderField: "x-request-id")

            if httpResponse.statusCode == 401 {
                throw MarketAPIClientError.unauthorized(requestId: requestId)
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                    throw MarketAPIClientError.backend(
                        statusCode: httpResponse.statusCode,
                        message: envelope.resolvedMessage,
                        requestId: requestId
                    )
                }
                throw MarketAPIClientError.backend(
                    statusCode: httpResponse.statusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                    requestId: requestId
                )
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw MarketAPIClientError.decodingFailed(requestId: requestId)
            }
        } catch let error as MarketAPIClientError {
            throw error
        } catch {
            throw MarketAPIClientError.transport(error.localizedDescription)
        }
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        try await request(
            path: path,
            method: method,
            accessToken: accessToken,
            queryItems: queryItems,
            body: Optional<String>.none
        )
    }

    private func resolvedAuthService() async throws -> any AuthServiceProtocol {
        guard let authService = await authContext.resolve() else {
            throw MarketAPIClientError.unconfigured
        }
        return authService
    }

    private func normalizedSymbol(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func encodedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
