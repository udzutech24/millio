import Foundation

struct RateSnapshot: Sendable {
    let source: RateSource
    let rates: [String: Double]
    let updatedAt: Double
    let fetchedAt: Double
}

protocol RateRepositoryProtocol: Sendable {
    func getLatestRates(source: RateSource, forceRefresh: Bool, allowStaleOnError: Bool) async throws -> RateSnapshot
}

actor RateRepository: RateRepositoryProtocol {
    static let shared: RateRepositoryProtocol = RateRepository()
    
    private struct CacheEntry {
        let snapshot: RateSnapshot
    }
    
    private var cache: [RateSource: CacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 12 * 3600
    
    func getLatestRates(source: RateSource, forceRefresh: Bool, allowStaleOnError: Bool) async throws -> RateSnapshot {
        let now = Date().timeIntervalSince1970
        
        if !forceRefresh, let cached = cache[source]?.snapshot, (now - cached.fetchedAt) < cacheTimeout {
            return cached
        }
        
        do {
            let snapshot = try await fetchLatestRates(source: source)
            cache[source] = CacheEntry(snapshot: snapshot)
            return snapshot
        } catch {
            if allowStaleOnError, let cached = cache[source]?.snapshot {
                return cached
            }
            throw error
        }
    }
    
    private func fetchLatestRates(source: RateSource) async throws -> RateSnapshot {
        guard let url = source.latestURL else {
            throw URLError(.badURL)
        }
        
        let fetchedAt = Date().timeIntervalSince1970
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        var rates: [String: Double]
        var updatedAt: Double = fetchedAt
        
        switch source {
        case .erapi:
            struct ERAPIResponse: Decodable {
                let result: String
                let rates: [String: Double]
                let time_last_update_unix: Int
            }
            
            let decoded = try JSONDecoder().decode(ERAPIResponse.self, from: data)
            guard decoded.result == "success" else {
                throw URLError(.cannotParseResponse)
            }
            rates = decoded.rates
            updatedAt = TimeInterval(decoded.time_last_update_unix)
            
        case .frankfurter:
            struct FrankfurterResponse: Decodable {
                let rates: [String: Double]
                let date: String?
            }
            
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            let eurRates = decoded.rates
            
            if let eurToUsd = eurRates["USD"] {
                var normalized: [String: Double] = [:]
                normalized.reserveCapacity(eurRates.count)
                
                for (code, eurRate) in eurRates where code != "USD" {
                    normalized[code] = eurRate / eurToUsd
                }
                rates = normalized
            } else {
                rates = eurRates
            }
            
            if let dateStr = decoded.date {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                
                if let date = df.date(from: dateStr) {
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
                    components.hour = 15
                    components.minute = 0
                    components.timeZone = TimeZone(secondsFromGMT: 0)
                    
                    if let dateWithTime = Calendar.current.date(from: components) {
                        updatedAt = dateWithTime.timeIntervalSince1970
                    } else {
                        updatedAt = date.timeIntervalSince1970
                    }
                }
            }
        }
        
        rates["USD"] = 1.0
        rates = rates
            .map { ($0.key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), $0.value) }
            .filter { !$0.0.isEmpty && $0.1 > 0 }
            .reduce(into: [String: Double]()) { $0[$1.0] = $1.1 }
        
        if rates.isEmpty {
            throw URLError(.cannotParseResponse)
        }
        
        return RateSnapshot(source: source, rates: rates, updatedAt: updatedAt, fetchedAt: fetchedAt)
    }
}

