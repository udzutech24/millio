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
    /// Последний известный набор курсов, доступный БЕЗ сети (прогрет с диска при инициализации).
    /// UI использует его, чтобы не показывать индикатор загрузки поверх уже готовых цифр.
    func currentRateSnapshot() -> RateSnapshot?
}

extension CurrencyRateServiceProtocol {
    /// Дефолт для тестовых даблов: «кэш неизвестен» — поведение как до появления снимка.
    func currentRateSnapshot() -> RateSnapshot? { nil }
}

// MARK: - Currency Rate Service

/// Общий сервис для получения курсов валют
/// Соответствует принципам Offline-First: кэширует курсы и работает без интернета
@MainActor
final class CurrencyRateService: CurrencyRateServiceProtocol {
    static let shared = CurrencyRateService(
        rateSource: RateSourcePreferenceStore.shared.preferred,
        rateRepository: RateRepository.shared
    )

    /// Источник курсов для данного экземпляра сервиса.
    private(set) var rateSource: RateSource
    var store: RateSourcePreferenceStore
    private let rateRepository: RateRepositoryProtocol
    private let historicalLoader: HTTPDataLoading
    private let frankfurterHistoricalProvider: HistoricalRateProvider
    private let rubHistoricalProvider: HistoricalRateProvider?
    private let cbrLatestProvider: CBRLatestRateProvider

    /// Провайдер цены крипто-валюты в USD (инжектируется извне, Core не зависит от MarketAPIClient).
    /// Принимает код валюты ("BTC"), возвращает цену в USD (например, 100000.0).
    var cryptoPriceProviderUSD: (@Sendable (String) async -> Double?)? = nil

    private var cachedRates: [String: Double] = ["USD": 1.0]
    private var lastUpdateTS: Double = 0
    private var activeSnapshot: RateSnapshot?
    private let cacheTimeout: TimeInterval = 12 * 3600 // 12 часов
    private var refreshTask: Task<Void, Never>?
    /// Инкрементируется при смене источника — защищает кэш от in-flight запросов старого источника.
    private var cacheGeneration: Int = 0
    
    init(
        rateSource: RateSource = .millio,
        store: RateSourcePreferenceStore = .shared,
        rateRepository: RateRepositoryProtocol = RateRepository.shared,
        historicalLoader: HTTPDataLoading = URLSession.shared,
        frankfurterHistoricalProvider: HistoricalRateProvider = FrankfurterHistoricalRateProvider(),
        rubHistoricalFallbackProvider: HistoricalRateProvider? = CBRHistoricalRateProvider(),
        cbrLatestProvider: CBRLatestRateProvider = CBRLatestRateProvider()
    ) {
        self.rateSource = rateSource
        self.store = store
        self.rateRepository = rateRepository
        self.historicalLoader = historicalLoader
        self.frankfurterHistoricalProvider = frankfurterHistoricalProvider
        self.rubHistoricalProvider = rubHistoricalFallbackProvider
        self.cbrLatestProvider = cbrLatestProvider
        // Синхронный прогрев из UserDefaults — конвертация и виджет работают мгновенно без сети.
        // Не используем async/actor чтобы избежать race condition с первым обращением к getRate().
        if rateSource == .custom {
            let customRates = CustomRateStore.shared.toUSDBase(currentPrimary: SettingsManager.shared.primaryCurrencyCode)
            if !customRates.isEmpty {
                cachedRates.merge(customRates) { _, new in new }
                lastUpdateTS = Date().timeIntervalSince1970
                // Ручные курсы — такой же полноценный снимок: без него UI считал бы, что курсов нет.
                activeSnapshot = RateSnapshot(
                    source: .custom,
                    rates: cachedRates,
                    updatedAt: lastUpdateTS,
                    fetchedAt: lastUpdateTS
                )
            }
        } else {
            let udKey = "rate_repo_rates_\(rateSource.rawValue)"
            let udFetchedKey = "rate_repo_fetched_at_\(rateSource.rawValue)"
            if let saved = UserDefaults.standard.dictionary(forKey: udKey) as? [String: Double], !saved.isEmpty {
                cachedRates = saved
                lastUpdateTS = UserDefaults.standard.double(forKey: udFetchedKey)
                activeSnapshot = RateSnapshot(
                    source: rateSource,
                    rates: saved,
                    updatedAt: UserDefaults.standard.double(forKey: "rate_repo_updated_at_\(rateSource.rawValue)"),
                    fetchedAt: lastUpdateTS
                )
                if let activeSnapshot {
                    _ = CurrencyRateSnapshotRevisionStore.save(activeSnapshot)
                }
            }
        }
    }

    /// Полный активный фиатный snapshot без сети.
    /// Все UI-consumer должны читать его через этот сервис, а не из `RateRepository` напрямую.
    func currentRateSnapshot() -> RateSnapshot? {
        activeSnapshot
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

    /// Возвращает true если хотя бы один из кодов — RUB.
    private func pairInvolvesRUB(_ f: String, _ t: String) -> Bool {
        f == "RUB" || t == "RUB"
    }

    /// Первый источник из цепочки (кроме текущего) с globalFiatDaily capability.
    private func globalFiatFallbackService() -> CurrencyRateService {
        CurrencyRateService(rateSource: .millio, rateRepository: rateRepository, historicalLoader: historicalLoader)
    }

    /// Получить курс конвертации: сколько единиц 'to' за 1 единицу 'from'
    func getRate(from: String, to: String) async -> Double? {
        let f = from.uppercased()
        let t = to.uppercased()

        if f == t { return 1.0 }

        // CBR покрывает только RUB-пары. Для прочих пар прозрачно роутим на globalFiat.
        if rateSource.capability.scope == .rubOfficialDaily, !pairInvolvesRUB(f, t) {
            AppLogger.log(.info, category: "CurrencyRateService", "CBR: pair \(f)→\(t) not RUB-involved, routing to globalFiat fallback")
            return await globalFiatFallbackService().getRate(from: f, to: t)
        }

        // Custom: кэш уже заполнен вручную введёнными курсами — обновление из сети не нужно.
        // Пары, отсутствующие в custom-таблице, прозрачно делегируем globalFiat-источнику.
        if rateSource == .custom {
            let rateFromUSD = f == "USD" ? 1.0 : cachedRates[f]
            let rateToUSD   = t == "USD" ? 1.0 : cachedRates[t]
            if let rFrom = rateFromUSD, let rTo = rateToUSD, rFrom > 0, rTo > 0 {
                return rTo / rFrom
            }
            AppLogger.log(.info, category: "CurrencyRateService", "Custom: pair \(f)→\(t) not in custom table, routing to globalFiat fallback")
            return await globalFiatFallbackService().getRate(from: f, to: t)
        }

        // Проверяем кэш и обновляем при необходимости
        let now = Date().timeIntervalSince1970
        let needsUpdate = cachedRates.count <= 1 || (now - lastUpdateTS) > cacheTimeout

        if needsUpdate {
            // A repository may have a persisted snapshot even when this service was created
            // before its own UserDefaults warm-up (or uses an injected repository in tests).
            // Read it before considering the network so an offline relaunch remains immediate.
            if cachedRates.count <= 1,
               let persisted = await rateRepository.peekCachedSnapshot(source: rateSource),
               !persisted.rates.isEmpty {
                adoptSnapshot(persisted, notify: false)
            }
            // A stale persisted quote is still more useful than a blocked local UI. Refresh it
            // opportunistically; waiting here made the finance graph and header spin during a
            // backend/provider outage even though a last known rate was already available.
            if cachedRates.count > 1 {
                Task { @MainActor [weak self] in
                    await self?.refreshRates()
                }
            } else {
                // No cached value exists, so there is nothing honest to present yet.
                await refreshRates()
            }
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

        // Official CBR daily data is authoritative for every RUB-involved historical pair.
        // Frankfurter remains the fallback for provider outages and the primary source for
        // non-RUB pairs. The persisted HistoricalRateStore cache sits in front of this method.
        if (f == "RUB" || t == "RUB"),
           let rubHistoricalProvider,
           let cbrRate = await rubHistoricalProvider.fetchRate(on: date, from: f, to: t, loader: historicalLoader) {
            return cbrRate
        }

        if let rate = await frankfurterHistoricalProvider.fetchRate(on: date, from: f, to: t, loader: historicalLoader) {
            return rate
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
        rubHistoricalProvider?.resetTransientCache()
    }

    /// Строит ограниченную цепочку fallback-источников без смешивания публичных провайдеров.
    func buildFallbackChain() -> [RateSource] {
        switch rateSource {
        case .millio:
            return [.millio, .erapi]
        case .erapi:
            return [.erapi, .millio]
        case .frankfurter:
            return [.frankfurter, .millio, .erapi]
        case .cbr, .custom:
            return [rateSource]
        }
    }

    /// Меняет глобальный источник, сбрасывает кэш и уведомляет подписчиков.
    /// Единственная точка записи store.preferred.
    func setRateSource(_ source: RateSource) {
        rateSource = source
        store.preferred = source
        cacheGeneration += 1
        refreshTask = nil
        cachedRates = ["USD": 1.0]
        lastUpdateTS = 0
        activeSnapshot = nil
        CurrencyRateSnapshotRevisionStore.clear()
        if source == .custom {
            let customRates = CustomRateStore.shared.toUSDBase(currentPrimary: SettingsManager.shared.primaryCurrencyCode)
            if !customRates.isEmpty {
                cachedRates.merge(customRates) { _, new in new }
                lastUpdateTS = Date().timeIntervalSince1970
                activeSnapshot = RateSnapshot(
                    source: .custom,
                    rates: cachedRates,
                    updatedAt: lastUpdateTS,
                    fetchedAt: lastUpdateTS
                )
                if let activeSnapshot {
                    _ = CurrencyRateSnapshotRevisionStore.save(activeSnapshot)
                }
            }
        }
        NotificationCenter.default.post(name: .currencyRateSourceDidChange, object: nil)
    }

    /// Обновить курсы из выбранного источника.
    private func refreshRates(force: Bool = false) async {
        // Custom-курсы — только ручной ввод, сетевого обновления нет.
        guard rateSource != .custom else { return }

        let now = Date().timeIntervalSince1970
        let needsUpdate = force || cachedRates.count <= 1 || (now - lastUpdateTS) > cacheTimeout
        guard needsUpdate else { return }

        // Дедупликация: если обновление уже выполняется — ждём его результата, новый запрос не отправляем.
        // Это предотвращает N параллельных HTTP-запросов при одновременном вызове getRate() из нескольких ViewModels.
        if let existing = refreshTask {
            await existing.value
            return
        }

        let generation = cacheGeneration
        let task = Task {
            // CBR имеет собственный XML-провайдер, не использует RateRepository.
            if self.rateSource.capability.scope == .rubOfficialDaily {
                do {
                    let rates = try await self.cbrLatestProvider.fetchRates(loader: self.historicalLoader)
                    guard self.cacheGeneration == generation else { return }
                    if !rates.isEmpty {
                        let snapshot = RateSnapshot(
                            source: self.rateSource,
                            rates: rates,
                            updatedAt: Date().timeIntervalSince1970,
                            fetchedAt: Date().timeIntervalSince1970
                        )
                        self.adoptSnapshot(snapshot)
                        UserDefaults.standard.set(rates, forKey: "rate_repo_rates_\(self.rateSource.rawValue)")
                        UserDefaults.standard.set(snapshot.fetchedAt, forKey: "rate_repo_fetched_at_\(self.rateSource.rawValue)")
                    }
                    return
                } catch {
                    AppLogger.log(.warning, category: "CurrencyRateService", "CBR latest rates failed: \(error.localizedDescription)")
                }
                // Если CBR недоступен — используем stale кэш из UserDefaults (offline-first).
                guard self.cacheGeneration == generation else { return }
                let udKey = "rate_repo_rates_\(self.rateSource.rawValue)"
                if let saved = UserDefaults.standard.dictionary(forKey: udKey) as? [String: Double], !saved.isEmpty {
                    self.adoptSnapshot(
                        RateSnapshot(
                            source: self.rateSource,
                            rates: saved,
                            updatedAt: UserDefaults.standard.double(forKey: "rate_repo_updated_at_\(self.rateSource.rawValue)"),
                            fetchedAt: UserDefaults.standard.double(forKey: "rate_repo_fetched_at_\(self.rateSource.rawValue)")
                        ),
                        notify: false
                    )
                }
                return
            }

            let chain = self.buildFallbackChain()
            for (index, source) in chain.enumerated() {
                do {
                    let snapshot = try await self.rateRepository.getLatestRates(source: source, forceRefresh: true, allowStaleOnError: false)
                    guard self.cacheGeneration == generation else { return }
                    if !snapshot.rates.isEmpty {
                        self.adoptSnapshot(snapshot)
                    }
                    return
                } catch {
                    let next = index + 1 < chain.count ? chain[index + 1].rawValue : "stale"
                    AppLogger.log(.warning, category: "CurrencyRateService", "Source \(source.rawValue) failed, trying \(next): \(error.localizedDescription)")
                }
            }

            guard self.cacheGeneration == generation else { return }
            // Все источники недоступны — используем последний известный кэш без сетевых запросов.
            // Это сохраняет работоспособность конвертера при полной блокировке сети (например, GFW).
            let fetchTime = Date().timeIntervalSince1970
            if let stale = await self.rateRepository.peekCachedSnapshot(source: self.rateSource), !stale.rates.isEmpty {
                self.adoptSnapshot(stale, notify: false)
                AppLogger.log(.info, category: "CurrencyRateService", "Using stale cached rates (age: \(Int((fetchTime - stale.fetchedAt) / 3600))h)")
            } else {
                AppLogger.log(.error, category: "CurrencyRateService", "All rate sources failed and no stale cache available")
            }
        }

        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func adoptSnapshot(_ snapshot: RateSnapshot, notify: Bool = true) {
        let previousRevision = activeSnapshot.map(CurrencyRateSnapshotRevisionStore.revision(for:))
        let revision = CurrencyRateSnapshotRevisionStore.save(snapshot)
        cachedRates = snapshot.rates
        lastUpdateTS = snapshot.fetchedAt
        activeSnapshot = snapshot

        guard notify, revision != previousRevision else { return }
        NotificationCenter.default.post(name: .currencyRateSnapshotDidChange, object: nil)
    }

    nonisolated static func makeLatestURL(for source: RateSource) -> URL? {
        source.latestURL
    }
}
