import Foundation

struct RateSnapshot: Sendable {
    let source: RateSource
    let rates: [String: Double]
    let updatedAt: Double
    let fetchedAt: Double
}

protocol RateRepositoryProtocol: Sendable {
    func getLatestRates(source: RateSource, forceRefresh: Bool, allowStaleOnError: Bool) async throws -> RateSnapshot
    /// Возвращает последний известный снимок из памяти/UserDefaults без сетевых запросов.
    /// Используется как последний резерв, когда все сетевые источники недоступны.
    func peekCachedSnapshot(source: RateSource) async -> RateSnapshot?
}

actor RateRepository: RateRepositoryProtocol {
    static let shared: RateRepositoryProtocol = RateRepository()

    private struct CacheEntry {
        let snapshot: RateSnapshot
    }

    private var cache: [RateSource: CacheEntry] = [:]
    private let cacheTimeout: TimeInterval = 12 * 3600

    // Короткий таймаут — не ждём зависшего источника дольше 10 сек на сотовой
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // MARK: - UserDefaults persistence keys

    private func udRatesKey(_ source: RateSource) -> String { "rate_repo_rates_\(source.rawValue)" }
    private func udUpdatedAtKey(_ source: RateSource) -> String { "rate_repo_updated_at_\(source.rawValue)" }
    private func udFetchedAtKey(_ source: RateSource) -> String { "rate_repo_fetched_at_\(source.rawValue)" }

    private func persist(_ snapshot: RateSnapshot) {
        let ud = UserDefaults.standard
        ud.set(snapshot.rates, forKey: udRatesKey(snapshot.source))
        ud.set(snapshot.updatedAt, forKey: udUpdatedAtKey(snapshot.source))
        ud.set(snapshot.fetchedAt, forKey: udFetchedAtKey(snapshot.source))
        // Дублируем в iCloud KV — выживает при переустановке приложения
        let kv = NSUbiquitousKeyValueStore.default
        kv.set(snapshot.rates, forKey: udRatesKey(snapshot.source))
        kv.set(snapshot.updatedAt, forKey: udUpdatedAtKey(snapshot.source))
        kv.set(snapshot.fetchedAt, forKey: udFetchedAtKey(snapshot.source))
        kv.synchronize()
    }

    private func loadPersisted(source: RateSource) -> RateSnapshot? {
        let ud = UserDefaults.standard
        // Сначала UserDefaults (быстрее), при переустановке fallback на iCloud KV
        if let rates = ud.dictionary(forKey: udRatesKey(source)) as? [String: Double], !rates.isEmpty {
            let updatedAt = ud.double(forKey: udUpdatedAtKey(source))
            let fetchedAt = ud.double(forKey: udFetchedAtKey(source))
            return RateSnapshot(source: source, rates: rates, updatedAt: updatedAt, fetchedAt: fetchedAt)
        }
        let kv = NSUbiquitousKeyValueStore.default
        guard let rates = kv.dictionary(forKey: udRatesKey(source)) as? [String: Double], !rates.isEmpty else { return nil }
        let updatedAt = kv.double(forKey: udUpdatedAtKey(source))
        let fetchedAt = kv.double(forKey: udFetchedAtKey(source))
        // Восстанавливаем в UserDefaults чтобы следующий старт был быстрым
        ud.set(rates, forKey: udRatesKey(source))
        ud.set(updatedAt, forKey: udUpdatedAtKey(source))
        ud.set(fetchedAt, forKey: udFetchedAtKey(source))
        return RateSnapshot(source: source, rates: rates, updatedAt: updatedAt, fetchedAt: fetchedAt)
    }

    // MARK: - Public API

    func getLatestRates(source: RateSource, forceRefresh: Bool, allowStaleOnError: Bool) async throws -> RateSnapshot {
        let now = Date().timeIntervalSince1970

        // Тёплый in-memory кэш — возвращаем сразу, если ещё актуален
        if !forceRefresh, let cached = cache[source]?.snapshot, (now - cached.fetchedAt) < cacheTimeout {
            return cached
        }

        // Если кэш протух (или его нет), сначала прогреваем из UserDefaults —
        // чтобы конвертация работала немедленно, пока идёт сетевой запрос
        if cache[source] == nil, let persisted = loadPersisted(source: source) {
            cache[source] = CacheEntry(snapshot: persisted)
        }

        do {
            let snapshot = try await fetchLatestRates(source: source)
            cache[source] = CacheEntry(snapshot: snapshot)
            persist(snapshot)
            return snapshot
        } catch {
            // Детальный лог для диагностики проблем на сотовой сети
            let urlErr = error as? URLError
            AppLogger.log(.warning, category: "RateRepository",
                "[\(source.rawValue)] fetch failed — code=\(urlErr?.code.rawValue.description ?? "?") msg=\(error.localizedDescription)")
            if allowStaleOnError, let cached = cache[source]?.snapshot {
                return cached
            }
            throw error
        }
    }

    func peekCachedSnapshot(source: RateSource) -> RateSnapshot? {
        if let cached = cache[source]?.snapshot { return cached }
        return loadPersisted(source: source)
    }

    private func fetchLatestRates(source: RateSource) async throws -> RateSnapshot {
        guard let url = source.latestURL else {
            throw URLError(.badURL)
        }

        let fetchedAt = Date().timeIntervalSince1970
        let (data, response) = try await RateRepository.urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            AppLogger.log(.error, category: "RateRepository", "[\(source.rawValue)] HTTP \(status) from \(url.host ?? "?")")
            throw URLError(.badServerResponse)
        }

        var rates: [String: Double]
        var updatedAt: Double = fetchedAt

        switch source {
        case .millio:
            // Формат совпадает с erapi: { "result": "success", "rates": {...}, "time_last_update_unix": ... }
            struct MillioRatesResponse: Decodable {
                let result: String
                let rates: [String: Double]
                let time_last_update_unix: Int
            }

            let decoded = try JSONDecoder().decode(MillioRatesResponse.self, from: data)
            guard decoded.result == "success" else {
                throw URLError(.cannotParseResponse)
            }
            rates = decoded.rates
            updatedAt = TimeInterval(decoded.time_last_update_unix)

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

        case .cbr:
            // CBR использует CBRLatestRateProvider, не RateRepository.
            // Этот путь не должен вызываться — CurrencyRateService обходит RateRepository для .cbr.
            throw URLError(.unsupportedURL)

        case .custom:
            // Custom-курсы не имеют сетевого источника — RateRepository не используется.
            throw URLError(.unsupportedURL)
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
