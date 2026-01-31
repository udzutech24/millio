//
//  CurrencyRateService.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

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
    
    /// Источник курсов для данного экземпляра сервиса.
    /// Глобально для приложения используется `.erapi`.
    private(set) var rateSource: RateSource
    private let rateRepository: RateRepositoryProtocol
    
    private var cachedRates: [String: Double] = ["USD": 1.0]
    private var lastUpdateTS: Double = 0
    private let cacheTimeout: TimeInterval = 12 * 3600 // 12 часов
    
    init(rateSource: RateSource = .erapi, rateRepository: RateRepositoryProtocol = RateRepository.shared) {
        self.rateSource = rateSource
        self.rateRepository = rateRepository
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
        guard let url = URL(string: "https://api.frankfurter.app/\(dateString)?from=\(from)&to=\(to)") else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            struct FrankfurterResponse: Decodable {
                let rates: [String: Double]
            }
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            return decoded.rates[to]
        } catch {
            AppLogger.log(.error, category: "CurrencyRateService", "Failed to fetch historical rate: \(error.localizedDescription)")
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
