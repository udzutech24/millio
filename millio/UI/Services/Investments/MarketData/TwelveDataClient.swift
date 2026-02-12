import Foundation

protocol MarketDataClientProtocol: Sendable {
    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol]
    func latestPrice(symbol: String, forceRefresh: Bool) async throws -> Double?
}

extension MarketDataClientProtocol {
    func searchSymbols(query: String) async throws -> [TwelveDataSymbol] {
        try await searchSymbols(query: query, outputSize: 20)
    }
}

struct TwelveDataSymbol: Decodable, Identifiable, Equatable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case symbol
        case instrumentName = "instrument_name"
        case exchange
        case micCode = "mic_code"
        case instrumentType = "instrument_type"
        case country
        case currency
    }
}

struct TwelveDataSearchResponse: Decodable, Sendable {
    let data: [TwelveDataSymbol]?
    let status: String?
    let code: Int?
    let message: String?
}

struct TwelveDataPriceResponse: Decodable, Sendable {
    let price: String?
    let status: String?
    let code: Int?
    let message: String?
}

enum TwelveDataClientError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case apiError(code: Int?, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return String(localized: "finances.market.error_missing_api_key")
        case .apiError(_, let message):
            return message
        case .invalidResponse:
            return String(localized: "finances.market.error_invalid_response")
        }
    }
}

actor TwelveDataCacheStore {
    private struct CacheEntry<Value: Sendable>: Sendable {
        let createdAt: Date
        let value: Value
    }

    private let ttl: TimeInterval
    private var searchCache: [String: CacheEntry<[TwelveDataSymbol]>] = [:]
    private var priceCache: [String: CacheEntry<Double>] = [:]

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func getSearch(for key: String) -> [TwelveDataSymbol]? {
        guard let entry = searchCache[key], Date().timeIntervalSince(entry.createdAt) < ttl else {
            searchCache[key] = nil
            return nil
        }
        return entry.value
    }

    func setSearch(_ value: [TwelveDataSymbol], for key: String) {
        searchCache[key] = CacheEntry(createdAt: Date(), value: value)
    }

    func getPrice(for key: String) -> Double? {
        guard let entry = priceCache[key], Date().timeIntervalSince(entry.createdAt) < ttl else {
            priceCache[key] = nil
            return nil
        }
        return entry.value
    }

    func setPrice(_ value: Double, for key: String) {
        priceCache[key] = CacheEntry(createdAt: Date(), value: value)
    }
}

final class TwelveDataClient: MarketDataClientProtocol {
    static let shared: MarketDataClientProtocol = TwelveDataClient()

    private struct ErrorEnvelope: Decodable {
        let status: String?
        let code: Int?
        let message: String?
    }

    private let session: URLSession
    private let apiKeyProvider: @Sendable () -> String?
    private let cacheStore: TwelveDataCacheStore

    init(
        session: URLSession = .shared,
        cacheTTL: TimeInterval = 3600,
        apiKeyProvider: @escaping @Sendable () -> String? = TwelveDataClient.loadAPIKeyFromInfoPlist
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
        self.cacheStore = TwelveDataCacheStore(ttl: cacheTTL)
    }

    func searchSymbols(query: String, outputSize: Int = 20) async throws -> [TwelveDataSymbol] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalizedQuery.isEmpty else {
            return []
        }

        if let cached = await cacheStore.getSearch(for: normalizedQuery) {
            return cached
        }

        let apiKey = try resolvedAPIKey()

        var components = URLComponents(string: "https://api.twelvedata.com/symbol_search")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: normalizedQuery),
            URLQueryItem(name: "outputsize", value: String(max(1, outputSize))),
            URLQueryItem(name: "apikey", value: apiKey)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwelveDataClientError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            throw parseAPIError(from: data) ?? URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TwelveDataSearchResponse.self, from: data)

        if let status = decoded.status?.lowercased(),
           status == "error" {
            throw TwelveDataClientError.apiError(
                code: decoded.code,
                message: decoded.message ?? String(localized: "finances.market.error_generic")
            )
        }

        let results = decoded.data ?? []
        await cacheStore.setSearch(results, for: normalizedQuery)
        return results
    }

    func latestPrice(symbol: String, forceRefresh: Bool = false) async throws -> Double? {
        let normalizedSymbol = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalizedSymbol.isEmpty else {
            return nil
        }

        if !forceRefresh,
           let cachedPrice = await cacheStore.getPrice(for: normalizedSymbol) {
            return cachedPrice
        }

        let apiKey = try resolvedAPIKey()

        var components = URLComponents(string: "https://api.twelvedata.com/price")
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: normalizedSymbol),
            URLQueryItem(name: "apikey", value: apiKey)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwelveDataClientError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            throw parseAPIError(from: data) ?? URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(TwelveDataPriceResponse.self, from: data)

        // TwelveData может вернуть ошибку JSON при HTTP 200.
        if let status = decoded.status?.lowercased(),
           status == "error" {
            throw TwelveDataClientError.apiError(
                code: decoded.code,
                message: decoded.message ?? String(localized: "finances.market.error_generic")
            )
        }

        guard let priceString = decoded.price,
              let price = Double(priceString) else {
            return nil
        }

        await cacheStore.setPrice(price, for: normalizedSymbol)
        return price
    }

    private func resolvedAPIKey() throws -> String {
        guard let apiKey = apiKeyProvider() else {
            throw TwelveDataClientError.missingAPIKey
        }
        return apiKey
    }

    private func parseAPIError(from data: Data) -> TwelveDataClientError? {
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return nil
        }

        let status = envelope.status?.lowercased() ?? ""
        guard status == "error" || envelope.message != nil else {
            return nil
        }

        return TwelveDataClientError.apiError(
            code: envelope.code,
            message: envelope.message ?? String(localized: "finances.market.error_generic")
        )
    }

    private static func loadAPIKeyFromInfoPlist() -> String? {
        guard let rawKey = Bundle.main.object(forInfoDictionaryKey: "TWELVE_DATA_API_KEY") as? String else {
            return nil
        }

        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("$("),
              !trimmed.hasSuffix(")") else {
            return nil
        }

        return trimmed
    }
}
