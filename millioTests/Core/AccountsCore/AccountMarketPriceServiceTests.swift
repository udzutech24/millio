import Foundation
import SwiftData
import Testing
@testable import millio

/// Минимальный мок живых котировок — переиспользует ТОТ ЖЕ протокол, что и старый мир
/// (`MarketDataClientProtocol`), без сети. `actor` — `Sendable`-безопасен при передаче в сервис.
actor AccountMarketPriceMockClient: MarketDataClientProtocol {
    var quotesBySymbol: [String: Double] = [:]
    var shouldThrow = false

    func setPrice(_ price: Double, for symbol: String) {
        quotesBySymbol[symbol.uppercased()] = price
    }

    func searchSymbols(query: String, outputSize: Int) async throws -> [TwelveDataSymbol] { [] }

    func latestQuote(symbol: String, forceRefresh: Bool) async throws -> AssetSummary? {
        guard let price = quotesBySymbol[symbol.uppercased()] else { return nil }
        return makeSummary(symbol: symbol, price: price)
    }

    func fetchQuotes(symbols: [String]) async throws -> [AssetSummary] {
        if shouldThrow {
            throw MarketAPIClientError.transport("mock offline")
        }
        return symbols.compactMap { symbol in
            guard let price = quotesBySymbol[symbol.uppercased()] else { return nil }
            return makeSummary(symbol: symbol, price: price)
        }
    }

    private func makeSummary(symbol: String, price: Double) -> AssetSummary {
        AssetSummary(
            symbol: symbol.uppercased(),
            canonicalSymbol: symbol.uppercased(),
            providerSymbol: symbol.uppercased(),
            name: nil,
            exchange: nil,
            micCode: nil,
            currency: "USD",
            price: price,
            previousClose: nil,
            change: nil,
            percentChange: nil,
            isMarketOpen: nil,
            resolutionStatus: .fresh,
            updatedAt: "2026-07-04T00:00:00.000Z",
            isStale: false
        )
    }
}

/// S9/AC10 (append-only кэш цен), AC4 (детерминизм реплея), S6 (форвард-филл выходного).
@Suite("AccountMarketPriceService")
@MainActor
struct AccountMarketPriceServiceTests {

    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext)
    }

    private func day(_ offset: Int, base: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Date {
        base.addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    // MARK: - Апсерт только сегодняшнего dayKey (S9/AC10)

    @Test
    func refreshTodayPricesInsertsRowForTodayOnly() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let accountService = AccountsCoreService(modelContext: ctx)
        let account = try accountService.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        try accountService.buy(account: account, quantity: 10, unitPrice: 100)

        let client = AccountMarketPriceMockClient()
        await client.setPrice(155, for: "AAPL")
        let priceService = AccountMarketPriceService(modelContext: ctx, marketDataClient: client)

        await priceService.refreshTodayPrices()

        let todayKey = AccountEvent.dayKey(for: Date())
        let rows = try ctx.fetch(FetchDescriptor<HistoricalAssetPrice>())
        #expect(rows.count == 1)
        #expect(rows.first?.dayKey == todayKey)
        #expect(rows.first?.price == 155)
    }

    /// Апсерт разрешён ТОЛЬКО для сегодняшнего dayKey — уже записанная ПРОШЛАЯ дата не трогается
    /// повторным вызовом `refreshTodayPrices` (append-only, AC10).
    @Test
    func refreshTodayPricesNeverTouchesPastDayKeyRows() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let accountService = AccountsCoreService(modelContext: ctx)
        let account = try accountService.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        try accountService.buy(account: account, quantity: 10, unitPrice: 100)

        let yesterdayKey = AccountEvent.dayKey(for: day(-1))
        let historicalRow = HistoricalAssetPrice(symbol: "AAPL", assetClass: .stock, dayKey: yesterdayKey, price: 120, source: "seed")
        ctx.insert(historicalRow)
        try ctx.save()

        let client = AccountMarketPriceMockClient()
        await client.setPrice(200, for: "AAPL")
        let priceService = AccountMarketPriceService(modelContext: ctx, marketDataClient: client)
        await priceService.refreshTodayPrices()

        let untouchedYesterday = try ctx.fetch(FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { $0.dayKey == yesterdayKey }
        )).first
        #expect(untouchedYesterday?.price == 120) // не тронуто новым refresh
    }

    /// Повторный вызов В ТОТ ЖЕ день — апсерт разрешён (сегодняшняя точка живая, обновляется intraday).
    @Test
    func refreshTodayPricesUpdatesSameDayRowOnRepeatedCalls() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let accountService = AccountsCoreService(modelContext: ctx)
        let account = try accountService.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        try accountService.buy(account: account, quantity: 10, unitPrice: 100)

        let client = AccountMarketPriceMockClient()
        let priceService = AccountMarketPriceService(modelContext: ctx, marketDataClient: client)

        await client.setPrice(150, for: "AAPL")
        await priceService.refreshTodayPrices()
        await client.setPrice(160, for: "AAPL") // цена изменилась в течение дня
        await priceService.refreshTodayPrices()

        let rows = try ctx.fetch(FetchDescriptor<HistoricalAssetPrice>())
        #expect(rows.count == 1) // одна и та же строка сегодняшнего dayKey, не дубликат
        #expect(rows.first?.price == 160)
    }

    /// Недоступность сети/бэкенда — no-op, кэш не трогается (счёт не выпадает из тотала,
    /// движок E упадёт на lastKnown из событий).
    @Test
    func refreshTodayPricesIsNoOpWhenClientThrows() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let accountService = AccountsCoreService(modelContext: ctx)
        _ = try accountService.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )

        let client = AccountMarketPriceMockClient()
        await client.setShouldThrow(true)
        let priceService = AccountMarketPriceService(modelContext: ctx, marketDataClient: client)

        await priceService.refreshTodayPrices()

        let rows = try ctx.fetch(FetchDescriptor<HistoricalAssetPrice>())
        #expect(rows.isEmpty)
    }

    // MARK: - Форвард-филл выходного/праздника (S6) + детерминизм (AC4/AC10)

    @Test
    func snapshotProviderForwardFillsToNearestPastCachedDay() throws {
        let (container, ctx) = try makeContext()
        _ = container
        // День 1 — цена есть, день 2 (выходной) — цены нет вовсе, день 3 — новая цена.
        ctx.insert(HistoricalAssetPrice(symbol: "AAPL", assetClass: .stock, dayKey: AccountEvent.dayKey(for: day(1)), price: 100, source: "test"))
        ctx.insert(HistoricalAssetPrice(symbol: "AAPL", assetClass: .stock, dayKey: AccountEvent.dayKey(for: day(3)), price: 130, source: "test"))
        try ctx.save()

        let priceService = AccountMarketPriceService(modelContext: ctx)
        let provider = priceService.makeSnapshotProvider(symbols: ["AAPL"])

        let forwardFilled = provider.price(symbol: "AAPL", assetClass: .stock, on: day(2))
        #expect(forwardFilled == 100) // ближайшая известная ≤ дата — день 1, НЕ день 3
    }

    /// AC4/AC10: два вызова подряд на тех же данных дают байт-в-байт одинаковый результат.
    @Test
    func snapshotProviderIsDeterministicAcrossRepeatedCalls() throws {
        let (container, ctx) = try makeContext()
        _ = container
        ctx.insert(HistoricalAssetPrice(symbol: "AAPL", assetClass: .stock, dayKey: AccountEvent.dayKey(for: day(1)), price: 100, source: "test"))
        try ctx.save()

        let priceService = AccountMarketPriceService(modelContext: ctx)
        let first = priceService.makeSnapshotProvider(symbols: ["AAPL"]).price(symbol: "AAPL", assetClass: .stock, on: day(1))
        let second = priceService.makeSnapshotProvider(symbols: ["AAPL"]).price(symbol: "AAPL", assetClass: .stock, on: day(1))
        #expect(first == second)
    }

    /// AC10 на уровне тотала: смена live-цены МЕНЯЕТ ТОЛЬКО сегодняшнюю точку графика,
    /// вчерашняя историческая точка остаётся неизменной байт-в-байт.
    @Test
    func changingTodayPriceOnlyAffectsTodayPointNotHistoricalPoints() async throws {
        let (container, ctx) = try makeContext()
        _ = container
        let accountService = AccountsCoreService(modelContext: ctx)
        let account = try accountService.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock), date: day(-10)
        )
        try accountService.buy(account: account, quantity: 10, unitPrice: 100, date: day(-10))

        let yesterdayKey = AccountEvent.dayKey(for: day(-1))
        ctx.insert(HistoricalAssetPrice(symbol: "AAPL", assetClass: .stock, dayKey: yesterdayKey, price: 140, source: "test"))
        try ctx.save()

        let priceService = AccountMarketPriceService(modelContext: ctx)
        let providerBeforeLiveChange = priceService.makeSnapshotProvider(symbols: ["AAPL"])
        let yesterdayBefore = providerBeforeLiveChange.price(symbol: "AAPL", assetClass: .stock, on: day(-1))

        // «Сегодняшняя» живая цена меняется (симулируем refresh) — вчерашняя запись не трогается.
        let todayKey = AccountEvent.dayKey(for: Date())
        ctx.insert(HistoricalAssetPrice(symbol: "AAPL", assetClass: .stock, dayKey: todayKey, price: 999, source: "test"))
        try ctx.save()

        let providerAfterLiveChange = priceService.makeSnapshotProvider(symbols: ["AAPL"])
        let yesterdayAfter = providerAfterLiveChange.price(symbol: "AAPL", assetClass: .stock, on: day(-1))

        #expect(yesterdayBefore == 140)
        #expect(yesterdayAfter == 140) // не изменилась
    }
}

private extension AccountMarketPriceMockClient {
    func setShouldThrow(_ value: Bool) {
        shouldThrow = value
    }
}
