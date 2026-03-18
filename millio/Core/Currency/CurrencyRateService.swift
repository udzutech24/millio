//
//  CurrencyRateService.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

protocol HTTPDataLoading {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataLoading {}

// MARK: - Currency Rate Service Protocol

/// Протокол сервиса курсов валют для dependency injection
@MainActor
protocol CurrencyRateServiceProtocol {
    func getRate(from: String, to: String) async -> Double?
    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double?
    func convert(amount: Double, from: String, to: String) async -> Double?
    func forceRefreshRates() async
}

// MARK: - Currency Rate Service

/// Общий сервис для получения курсов валют
/// Соответствует принципам Offline-First: кэширует курсы и работает без интернета
@MainActor
final class CurrencyRateService: CurrencyRateServiceProtocol {
    static let shared = CurrencyRateService(rateSource: .erapi, rateRepository: RateRepository.shared)
    private static let frankfurterHistoricalSupportedCurrencies: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD",
        "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK",
        "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR"
    ]
    
    /// Источник курсов для данного экземпляра сервиса.
    /// Глобально для приложения используется `.erapi`.
    private(set) var rateSource: RateSource
    private let rateRepository: RateRepositoryProtocol
    private let historicalLoader: HTTPDataLoading
    
    private var cachedRates: [String: Double] = ["USD": 1.0]
    private var lastUpdateTS: Double = 0
    private let cacheTimeout: TimeInterval = 12 * 3600 // 12 часов
    private var knownHistoricalUnsupportedPairs: Set<String> = []
    private var knownHistoricalUnavailableRequests: Set<String> = []
    private var historicalFailureLogDedup: Set<String> = []
    
    init(
        rateSource: RateSource = .erapi,
        rateRepository: RateRepositoryProtocol = RateRepository.shared,
        historicalLoader: HTTPDataLoading = URLSession.shared
    ) {
        self.rateSource = rateSource
        self.rateRepository = rateRepository
        self.historicalLoader = historicalLoader
    }
    
    /// Получить курс конвертации: сколько единиц 'to' за 1 единицу 'from'
    func getRate(from: String, to: String) async -> Double? {
        let f = from.uppercased()
        let t = to.uppercased()
        
        if f == t { return 1.0 }
        
        // Проверяем кэш и обновляем при необходимости
        let now = Date().timeIntervalSince1970
        let needsUpdate = cachedRates.count <= 1 || (now - lastUpdateTS) > cacheTimeout
        
        if needsUpdate {
            await refreshRates()
        }
        
        // Получаем курсы через USD
        let rateFromUSD = f == "USD" ? 1.0 : cachedRates[f]
        let rateToUSD = t == "USD" ? 1.0 : cachedRates[t]
        
        guard let rFrom = rateFromUSD, let rTo = rateToUSD, rFrom > 0, rTo > 0 else {
            return nil
        }
        
        // 1 FROM = (rTo / rFrom) TO
        return rTo / rFrom
    }
    
    /// Конвертировать сумму из одной валюты в другую
    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }
    
    /// Получить исторический курс на дату (дневная гранулярность)
    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        let f = from.uppercased()
        let t = to.uppercased()
        
        if f == t { return 1.0 }
        
        if Calendar.current.isDateInToday(date) {
            return await getRate(from: f, to: t)
        }
        
        // Исторические курсы берем через Frankfurter (ECB)
        return await fetchFrankfurterRate(on: date, from: f, to: t)
    }
    
    /// Получить список доступных валют из текущего источника
    /// USD всегда доступен
    func getAvailableCurrencies() -> [String] {
        var currencies = Set(cachedRates.keys)
        currencies.insert("USD") // USD всегда доступен
        return Array(currencies).sorted()
    }
    
    /// Явно обновить курсы из API (принудительная загрузка)
    /// Используется когда нужно гарантировать наличие актуальных курсов
    func forceRefreshRates() async {
        await refreshRates(force: true)
    }
    
    /// Обновить курсы из выбранного источника
    private func refreshRates(force: Bool = false) async {
        let source = rateSource
        let now = Date().timeIntervalSince1970
        let needsUpdate = force || cachedRates.count <= 1 || (now - lastUpdateTS) > cacheTimeout
        
        do {
            let snapshot = try await rateRepository.getLatestRates(source: source, forceRefresh: needsUpdate, allowStaleOnError: true)
            if !snapshot.rates.isEmpty {
                cachedRates = snapshot.rates
                lastUpdateTS = snapshot.updatedAt
            }
        } catch {
            // Оставляем старые значения в кэше
            AppLogger.log(.error, category: "CurrencyRateService", "Failed to refresh rates: \(error.localizedDescription)")
        }
    }

    nonisolated static func makeLatestURL(for source: RateSource) -> URL? {
        source.latestURL
    }
    
    private func fetchFrankfurterRate(on date: Date, from: String, to: String) async -> Double? {
        let dateString = formatDateForFrankfurter(date)
        let pairKey = "\(from)->\(to)"
        let requestKey = "\(dateString)|\(pairKey)"

        // Frankfurter не публикует все валюты. Например, RUB отсутствует в справочнике
        // доступных symbols, поэтому такие запросы гарантированно не дадут exact-курс.
        guard Self.frankfurterHistoricalSupportedCurrencies.contains(from),
              Self.frankfurterHistoricalSupportedCurrencies.contains(to) else {
            knownHistoricalUnsupportedPairs.insert(pairKey)
            knownHistoricalUnavailableRequests.insert(requestKey)
            return nil
        }

        // Для явно неподдерживаемых пар не делаем повторные сетевые запросы.
        if knownHistoricalUnsupportedPairs.contains(pairKey) {
            return nil
        }

        // Для уже известных miss по точной дате и паре повторно в сеть не ходим.
        if knownHistoricalUnavailableRequests.contains(requestKey) {
            return nil
        }

        guard let url = URL(string: "https://api.frankfurter.app/\(dateString)?from=\(from)&to=\(to)") else {
            return nil
        }
        
        do {
            let (data, response) = try await historicalLoader.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard (200..<300).contains(http.statusCode) else {
                let statusCode = http.statusCode
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let bodySnippet = body?.prefix(180) ?? ""
                let logKey = "\(requestKey)|\(statusCode)"

                if historicalFailureLogDedup.insert(logKey).inserted {
                    AppLogger.log(
                        .warning,
                        category: "CurrencyRateService",
                        "Historical rate API HTTP \(statusCode) for \(pairKey) on \(dateString). \(bodySnippet)"
                    )
                }

                // Частые ожидаемые причины: неподдерживаемая валюта или rate limit.
                // Не эскалируем как -1011 и не повторяем запросы для неподдерживаемых пар.
                // Важно: HTTP 404 у Frankfurter часто означает “нет данных на эту дату”
                // (например, выходной/праздник), и это НЕ означает, что валютная пара
                // неподдерживается. Поэтому 404 не должен банить пару навсегда.
                if statusCode == 400 {
                    knownHistoricalUnsupportedPairs.insert(pairKey)
                    knownHistoricalUnavailableRequests.insert(requestKey)
                    return nil
                }
                if statusCode == 404 {
                    knownHistoricalUnavailableRequests.insert(requestKey)
                    return nil
                }
                if statusCode == 429 {
                    knownHistoricalUnavailableRequests.insert(requestKey)
                    return nil
                }

                throw URLError(.badServerResponse)
            }
            
            struct FrankfurterResponse: Decodable {
                let rates: [String: Double]
            }
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            guard let rate = decoded.rates[to] else {
                knownHistoricalUnavailableRequests.insert(requestKey)
                return nil
            }
            return rate
        } catch {
            let nsError = error as NSError
            let logKey = "\(requestKey)|\(nsError.domain)|\(nsError.code)"
            if historicalFailureLogDedup.insert(logKey).inserted {
                AppLogger.log(
                    .error,
                    category: "CurrencyRateService",
                    "Failed to fetch historical rate for \(pairKey) on \(dateString): \(error.localizedDescription)"
                )
            }
            return nil
        }
    }
    
    private func formatDateForFrankfurter(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
