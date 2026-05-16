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
    static let shared = CurrencyRateService(rateSource: .millio, rateRepository: RateRepository.shared)
    
    /// Источник курсов для данного экземпляра сервиса.
    /// Глобально для приложения используется `.erapi`.
    private(set) var rateSource: RateSource
    private let rateRepository: RateRepositoryProtocol
    private let historicalLoader: HTTPDataLoading
    private let frankfurterHistoricalProvider: HistoricalRateProvider
    private let rubHistoricalFallbackProvider: HistoricalRateProvider?
    
    /// Провайдер цены крипто-валюты в USD (инжектируется извне, Core не зависит от MarketAPIClient).
    /// Принимает код валюты ("BTC"), возвращает цену в USD (например, 100000.0).
    var cryptoPriceProviderUSD: (@Sendable (String) async -> Double?)? = nil

    private var cachedRates: [String: Double] = ["USD": 1.0]
    private var lastUpdateTS: Double = 0
    private let cacheTimeout: TimeInterval = 12 * 3600 // 12 часов
    private var refreshTask: Task<Void, Never>?
    
    init(
        rateSource: RateSource = .erapi,
        rateRepository: RateRepositoryProtocol = RateRepository.shared,
        historicalLoader: HTTPDataLoading = URLSession.shared,
        frankfurterHistoricalProvider: HistoricalRateProvider = FrankfurterHistoricalRateProvider(),
        rubHistoricalFallbackProvider: HistoricalRateProvider? = CBRHistoricalRateProvider()
    ) {
        self.rateSource = rateSource
        self.rateRepository = rateRepository
        self.historicalLoader = historicalLoader
        self.frankfurterHistoricalProvider = frankfurterHistoricalProvider
        self.rubHistoricalFallbackProvider = rubHistoricalFallbackProvider
        // Синхронный прогрев из UserDefaults — конвертация и виджет работают мгновенно без сети.
        // Не используем async/actor чтобы избежать race condition с первым обращением к getRate().
        let udKey = "rate_repo_rates_\(rateSource.rawValue)"
        let udFetchedKey = "rate_repo_fetched_at_\(rateSource.rawValue)"
        if let saved = UserDefaults.standard.dictionary(forKey: udKey) as? [String: Double], !saved.isEmpty {
            cachedRates = saved
            lastUpdateTS = UserDefaults.standard.double(forKey: udFetchedKey)
        }
    }
    
    /// Синхронно возвращает курс из текущего in-memory кэша без сетевых запросов.
    /// Используется для мгновенного показа stale данных, пока идёт фоновое обновление.
    func getCachedRate(from: String, to: String) -> Double? {
        let f = from.uppercased()
        let t = to.uppercased()
        if f == t { return 1.0 }
        let rateFromUSD = f == "USD" ? 1.0 : cachedRates[f]
        let rateToUSD = t == "USD" ? 1.0 : cachedRates[t]
        guard let rFrom = rateFromUSD, let rTo = rateToUSD, rFrom > 0, rTo > 0 else { return nil }
        return rTo / rFrom
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
        
        // Для валют, отсутствующих в фиат-кэше (напр., BTC), запрашиваем цену в USD у внешнего провайдера
        if let provider = cryptoPriceProviderUSD {
            if f != "USD", cachedRates[f] == nil {
                if let priceUSD = await provider(f), priceUSD > 0 {
                    cachedRates[f] = 1.0 / priceUSD
                }
            }
            if t != "USD", cachedRates[t] == nil {
                if let priceUSD = await provider(t), priceUSD > 0 {
                    cachedRates[t] = 1.0 / priceUSD
                }
            }
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

        if let rate = await frankfurterHistoricalProvider.fetchRate(on: date, from: f, to: t, loader: historicalLoader) {
            return rate
        }

        if (f == "RUB" || t == "RUB"),
           let rubHistoricalFallbackProvider,
           let fallbackRate = await rubHistoricalFallbackProvider.fetchRate(on: date, from: f, to: t, loader: historicalLoader) {
            return fallbackRate
        }

        return nil
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

    /// Сбрасывает in-memory кэш недоступных исторических запросов.
    /// Нужен для ручного "Refresh rates", чтобы временные ошибки не
    /// фиксировали дату/пару как недоступную до перезапуска приложения.
    func resetHistoricalUnavailableRequestCache() {
        frankfurterHistoricalProvider.resetTransientCache()
        rubHistoricalFallbackProvider?.resetTransientCache()
    }
    
    /// Обновить курсы из выбранного источника.
    /// Цепочка fallback: millio → erapi → frankfurter → stale-кэш (без сети).
    /// Последовательность фиксирована и не зависит от rateSource, чтобы гарантировать
    /// доступность конвертера в любой сетевой среде (в т.ч. при блокировках, например GFW).
    private func refreshRates(force: Bool = false) async {
        let now = Date().timeIntervalSince1970
        let needsUpdate = force || cachedRates.count <= 1 || (now - lastUpdateTS) > cacheTimeout
        guard needsUpdate else { return }

        // Дедупликация: если обновление уже выполняется — ждём его результата, новый запрос не отправляем.
        // Это предотвращает N параллельных HTTP-запросов при одновременном вызове getRate() из нескольких ViewModels.
        if let existing = refreshTask {
            await existing.value
            return
        }

        let task = Task {
            let chain: [RateSource] = [.millio, .erapi, .frankfurter]
            for (index, source) in chain.enumerated() {
                do {
                    let snapshot = try await self.rateRepository.getLatestRates(source: source, forceRefresh: true, allowStaleOnError: false)
                    if !snapshot.rates.isEmpty {
                        self.cachedRates = snapshot.rates
                        self.lastUpdateTS = snapshot.updatedAt
                    }
                    return
                } catch {
                    let next = index + 1 < chain.count ? chain[index + 1].rawValue : "stale"
                    AppLogger.log(.warning, category: "CurrencyRateService", "Source \(source.rawValue) failed, trying \(next): \(error.localizedDescription)")
                }
            }

            // Все источники недоступны — используем последний известный кэш без сетевых запросов.
            // Это сохраняет работоспособность конвертера при полной блокировке сети (например, GFW).
            let fetchTime = Date().timeIntervalSince1970
            if let stale = await self.rateRepository.peekCachedSnapshot(source: self.rateSource), !stale.rates.isEmpty {
                self.cachedRates = stale.rates
                self.lastUpdateTS = stale.updatedAt
                AppLogger.log(.info, category: "CurrencyRateService", "Using stale cached rates (age: \(Int((fetchTime - stale.fetchedAt) / 3600))h)")
            } else {
                AppLogger.log(.error, category: "CurrencyRateService", "All rate sources failed and no stale cache available")
            }
        }

        refreshTask = task
        await task.value
        refreshTask = nil
    }

    nonisolated static func makeLatestURL(for source: RateSource) -> URL? {
        source.latestURL
    }
}
