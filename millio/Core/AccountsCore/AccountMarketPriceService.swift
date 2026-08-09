import Foundation
import SwiftData

/// Реальная реализация котировок для нового ядра поверх ДЕЙСТВУЮЩЕГО источника живых цен
/// (`MarketDataClientProtocol`, тот же клиент, что питает старый мир `Investment.lastKnownUnitPrice`
/// через `FinanceMarketDataService`) — второй источник котировок НЕ заводим (S9: не плодить клиентов
/// к одному и тому же провайдеру, не жечь квоту дважды).
///
/// Двухшаговая архитектура — протокол `MarketPriceProviding.price(on:)` СИНХРОННЫЙ (реплей может идти
/// в фоновом `@ModelActor`, сетевой async-вызов внутри него невозможен и не нужен по S4):
/// 1. `refreshTodayPrices()` — асинхронно опрашивает live-квоты, апсертит СЕГОДНЯШНИЙ `dayKey` в
///    append-only кэш `HistoricalAssetPrice` (апсерт разрешён ТОЛЬКО для сегодня — S9/AC10: смена
///    live-цены в течение дня двигает ТОЛЬКО сегодняшнюю точку, прошлые дни неприкосновенны).
/// 2. `makeSnapshotProvider(symbols:)` — синхронно вычитывает уже накопленный кэш и возвращает
///    `Sendable`-снэпшот (`CachedPriceSnapshot`), которым реплей пользуется без единого обращения к сети.
@MainActor
final class AccountMarketPriceService {
    private let modelContext: ModelContext
    private let marketDataClient: MarketDataClientProtocol

    init(modelContext: ModelContext, marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared) {
        self.modelContext = modelContext
        self.marketDataClient = marketDataClient
    }

    // MARK: - Обновление (сеть, только СЕГОДНЯШНИЙ dayKey)

    /// Опрашивает live-котировки для символов активных `.marketInvestment`-счетов нового ядра и
    /// апсертит сегодняшнюю точку кэша. Недоступность (auth/network error, выходной без квоты) —
    /// молчаливый no-op: кэш не трогается, реплей упадёт на последнюю известную цену из кэша/событий
    /// (см. `AccountBalanceEngine.marketBalance` — счёт НЕ выпадает из тотала).
    func refreshTodayPrices() async {
        let marketKindRaw = AccountKind.marketInvestment.rawValue
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.kindRaw == marketKindRaw && $0.archivedAt == nil }
        )
        guard let accounts = try? modelContext.fetch(descriptor), !accounts.isEmpty else { return }

        var symbolToClass: [String: MarketAssetClass] = [:]
        for account in accounts {
            guard let meta = account.marketMeta else { continue }
            symbolToClass[meta.symbol.uppercased()] = meta.assetClass
        }
        guard !symbolToClass.isEmpty else { return }

        guard let quotes = try? await marketDataClient.fetchQuotes(symbols: Array(symbolToClass.keys)) else { return }

        let todayKey = AccountEvent.dayKey(for: Date())
        var didUpdate = false
        for quote in quotes {
            guard let price = quote.price, price > 0 else { continue }
            for key in quote.quoteLookupKeys {
                guard let assetClass = symbolToClass[key] else { continue }
                upsertTodayPrice(symbol: key, assetClass: assetClass, dayKey: todayKey, price: Decimal(price))
                didUpdate = true
            }
        }
        if didUpdate {
            try? modelContext.save()
        }
    }

    /// Cache-first historical warm-up. It performs at most one chart request per missing symbol,
    /// never one request per account/day. Existing closed rows remain immutable.
    func prefetchHistoricalPrices(on dates: [Date], accounts: [Account]) async {
        let requestedDayKeys = Set(dates.map { AccountEvent.dayKey(for: $0) })
        guard !requestedDayKeys.isEmpty else { return }

        var instruments: [String: MarketAssetClass] = [:]
        for account in accounts where account.kind == .marketInvestment {
            guard let meta = account.marketMeta else { continue }
            instruments[meta.symbol.uppercased()] = meta.assetClass
        }
        guard !instruments.isEmpty else { return }

        let rows = (try? modelContext.fetch(FetchDescriptor<HistoricalAssetPrice>())) ?? []
        var existingKeysBySymbol: [String: Set<String>] = [:]
        for row in rows {
            existingKeysBySymbol[row.symbol, default: []].insert(row.dayKey)
        }

        let outputSize = historicalOutputSize(for: dates)
        var inserted = false
        for symbol in instruments.keys.sorted() {
            let cachedKeys = existingKeysBySymbol[symbol] ?? []
            guard let assetClass = instruments[symbol] else { continue }
            if hasHistoricalCoverage(
                requestedDayKeys: requestedDayKeys,
                cachedDayKeys: cachedKeys,
                assetClass: assetClass
            ) { continue }
            guard let response = try? await marketDataClient.assetChart(
                symbol: symbol,
                interval: "1day",
                outputSize: outputSize
            ) else { continue }

            for point in response.points {
                guard let close = point.close, close.isFinite, close > 0,
                      let dayKey = historicalDayKey(point.datetime),
                      existingKeysBySymbol[symbol]?.contains(dayKey) != true else { continue }
                modelContext.insert(HistoricalAssetPrice(
                    symbol: symbol,
                    assetClass: assetClass,
                    dayKey: dayKey,
                    price: Decimal(close),
                    source: "historical:market-backend|tz=\(TimeZone.current.identifier)"
                ))
                existingKeysBySymbol[symbol, default: []].insert(dayKey)
                inserted = true
            }
        }
        if inserted { try? modelContext.save() }
    }

    private func hasHistoricalCoverage(
        requestedDayKeys: Set<String>,
        cachedDayKeys: Set<String>,
        assetClass: MarketAssetClass
    ) -> Bool {
        let policy: HistoricalValuationCalendarPolicy = assetClass == .crypto
            ? .crypto24x7(id: "historical-crypto-24x7-v1")
            : .exchange(id: "historical-market-business-days-v1")
        return requestedDayKeys.allSatisfy { requested in
            if cachedDayKeys.contains(requested) { return true }
            return cachedDayKeys.contains { candidate in
                policy.allowsPreviousClose(from: candidate, for: requested)
            }
        }
    }

    private func historicalOutputSize(for dates: [Date]) -> Int {
        guard let first = dates.min(), let last = dates.max() else { return 5 }
        let days = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        // Daily provider series contains trading days; headroom covers holidays and range edges.
        return min(5_000, max(5, Int((Double(max(0, days)) * 0.8).rounded(.up)) + 10))
    }

    private func historicalDayKey(_ raw: String) -> String? {
        let prefix = String(raw.prefix(10))
        guard prefix.count == 10 else { return nil }
        let characters = Array(prefix)
        guard characters[4] == "-", characters[7] == "-",
              characters.enumerated().allSatisfy({ index, character in
                  index == 4 || index == 7 || character.isNumber
              }) else { return nil }
        return prefix
    }

    /// Апсерт ТОЛЬКО сегодняшнего dayKey — append-only гарантия (S9/AC10) держится на том, что
    /// это единственное место записи в `HistoricalAssetPrice`, и оно никогда не трогает прошлые дни.
    private func upsertTodayPrice(symbol: String, assetClass: MarketAssetClass, dayKey: String, price: Decimal) {
        let source = "market-backend|tz=\(TimeZone.current.identifier)"
        let descriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { $0.symbol == symbol && $0.dayKey == dayKey }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.price = price
            existing.fetchedAt = Date()
            existing.source = source
        } else {
            let record = HistoricalAssetPrice(
                symbol: symbol,
                assetClass: assetClass,
                dayKey: dayKey,
                price: price,
                source: source
            )
            modelContext.insert(record)
        }
    }

    // MARK: - Синхронный снэпшот для реплея (без сети)

    /// Единственный способ получить `MarketPriceProviding` для реплея — читает уже накопленный
    /// кэш ОДНИМ запросом и возвращает неизменяемый `Sendable`-снэпшот (безопасно передавать в
    /// фоновый `AccountSnapshotRebuilder`, S4). Сеть доступна только предварительному prefetch;
    /// реплей всегда остаётся чистым и детерминированным.
    func makeSnapshotProvider(symbols: [String]) -> MarketPriceProviding {
        let upperSymbols = Array(Set(symbols.map { $0.uppercased() }))
        guard !upperSymbols.isEmpty else { return EmptyMarketPriceProvider() }

        let descriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { upperSymbols.contains($0.symbol) }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []

        var pricesBySymbol: [String: [String: Decimal]] = [:]
        for row in rows {
            pricesBySymbol[row.symbol, default: [:]][row.dayKey] = row.price
        }
        return CachedPriceSnapshot(pricesBySymbol: pricesBySymbol)
    }
}

/// Провайдер-заглушка для реплея без единого рыночного счёта (нет символов — нечего искать).
private struct EmptyMarketPriceProvider: MarketPriceProviding {
    func price(symbol: String, assetClass: MarketAssetClass, on date: Date) -> Decimal? { nil }
}

/// Sendable-снэпшот кэша цен: читается ОДИН РАЗ при создании, дальше только чистые словарные
/// lookup'ы — детерминировано (AC4/AC10: повторный вызов на тех же данных даёт байт-в-байт тот же
/// результат). Форвард-филл выходного/праздника (S6): ближайшая известная дата СТРОГО ≤ запрошенной,
/// вычисляется на лету из уже загруженного словаря (в кэш не пишется — детерминизм не требует записи,
/// только чистоты вычисления, см. докстринг `AccountMarketPriceService`).
struct CachedPriceSnapshot: MarketPriceProviding, Sendable {
    let pricesBySymbol: [String: [String: Decimal]]

    func price(symbol: String, assetClass: MarketAssetClass, on date: Date) -> Decimal? {
        let key = symbol.uppercased()
        guard let byDay = pricesBySymbol[key], !byDay.isEmpty else { return nil }
        let requestedKey = AccountEvent.dayKey(for: date)
        if let exact = byDay[requestedKey] { return exact }
        let candidateKey = byDay.keys.filter { $0 <= requestedKey }.max()
        return candidateKey.flatMap { byDay[$0] }
    }
}
