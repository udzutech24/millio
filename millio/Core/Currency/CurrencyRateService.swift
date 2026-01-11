//
//  CurrencyRateService.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

// MARK: - Currency Rate Service

/// Общий сервис для получения курсов валют
/// Использует тот же источник курсов, что и конвертер валют
/// Соответствует принципам Offline-First: кэширует курсы и работает без интернета

/// Общий сервис для получения курсов валют
/// Использует тот же источник курсов, что и конвертер валют
@MainActor
final class CurrencyRateService {
    static let shared = CurrencyRateService()
    
    private var cachedRates: [String: Double] = ["USD": 1.0]
    private var lastUpdateTS: Double = 0
    private let cacheTimeout: TimeInterval = 12 * 3600 // 12 часов
    
    private init() {}
    
    /// Получить текущий источник курсов из настроек
    private var currentRateSource: RateSource {
        let stored = UserDefaults.standard.string(forKey: "conv_rate_source") ?? "erapi"
        return RateSource(rawValue: stored) ?? .erapi
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
    
    /// Обновить курсы из выбранного источника
    private func refreshRates() async {
        let source = currentRateSource
        
        do {
            let url: URL
            switch source {
            case .erapi:
                url = URL(string: "https://open.er-api.com/v6/latest/USD")!
            case .exchangerateHost:
                url = URL(string: "https://api.exchangerate.host/latest?base=USD")!
            case .frankfurter:
                url = URL(string: "https://api.frankfurter.app/latest?from=USD")!
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            var rates: [String: Double] = [:]
            var updateTS: Double = Date().timeIntervalSince1970
            
            switch source {
            case .erapi:
                struct ERAPIResponse: Decodable {
                    let result: String
                    let rates: [String: Double]
                    let time_last_update_unix: Int
                }
                let decoded = try JSONDecoder().decode(ERAPIResponse.self, from: data)
                guard decoded.result == "success" else { throw URLError(.cannotParseResponse) }
                rates = decoded.rates
                updateTS = TimeInterval(decoded.time_last_update_unix)
                
            case .exchangerateHost:
                struct ExchangeRateHostResponse: Decodable {
                    let success: Bool?
                    let rates: [String: Double]?
                    let quotes: [String: Double]?
                    let timestamp: Int?
                    let date: String?
                }
                let decoded = try JSONDecoder().decode(ExchangeRateHostResponse.self, from: data)
                if let success = decoded.success, !success {
                    throw URLError(.cannotParseResponse)
                }
                if let ratesDict = decoded.rates {
                    rates = ratesDict
                } else if let quotes = decoded.quotes {
                    for (key, value) in quotes {
                        let upperKey = key.uppercased()
                        if upperKey.hasPrefix("USD"), upperKey.count == 6 {
                            let currencyCode = String(upperKey.dropFirst(3))
                            rates[currencyCode] = value
                        }
                    }
                }
                if let timestamp = decoded.timestamp {
                    updateTS = TimeInterval(timestamp)
                } else if let dateStr = decoded.date {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    df.locale = Locale(identifier: "en_US_POSIX")
                    df.timeZone = TimeZone(secondsFromGMT: 0)
                    if let date = df.date(from: dateStr) {
                        updateTS = date.timeIntervalSince1970
                    }
                }
                
            case .frankfurter:
                struct FrankfurterResponse: Decodable {
                    let rates: [String: Double]
                    let date: String
                }
                let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
                let eurRates = decoded.rates
                if let eurToUsd = eurRates["USD"] {
                    for (code, eurRate) in eurRates {
                        if code != "USD" {
                            rates[code] = eurRate / eurToUsd
                        }
                    }
                } else {
                    rates = eurRates
                }
                // Парсим дату из ответа (формат YYYY-MM-DD)
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = df.date(from: decoded.date) {
                    // Устанавливаем время на 16:00 CET (15:00 UTC) - время обновления Frankfurter
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
                    components.hour = 15
                    components.minute = 0
                    components.timeZone = TimeZone(secondsFromGMT: 0)
                    if let dateWithTime = Calendar.current.date(from: components) {
                        updateTS = dateWithTime.timeIntervalSince1970
                    } else {
                        updateTS = date.timeIntervalSince1970
                    }
                }
            }
            
            rates["USD"] = 1.0
            rates = rates.filter { !$0.key.isEmpty && $0.value > 0 }
            
            if !rates.isEmpty {
                cachedRates = rates
                lastUpdateTS = updateTS
            }
        } catch {
            // Оставляем старые значения в кэше
            AppLogger.log(.error, category: "CurrencyRateService", "Failed to refresh rates: \(error.localizedDescription)")
        }
    }
}
