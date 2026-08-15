import Foundation
import SwiftData
import Testing
@testable import millio

/// Mock-курс с историческими точками по дате — нужен чтобы доказать AC13: историческая точка
/// использует курс СВОЕЙ даты, а не сегодняшний (иначе тест был бы неотличим от константного курса).
@MainActor
final class DateAwareMockRateService: CurrencyRateServiceProtocol {
    var todayRate: Double = 110
    var historicalRatesByDayKey: [String: Double] = [:]
    private(set) var historicalCallCount = 0

    func getRate(from: String, to: String) async -> Double? {
        if from.uppercased() == to.uppercased() { return 1 }
        return todayRate
    }

    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        historicalCallCount += 1
        if from.uppercased() == to.uppercased() { return 1 }
        return historicalRatesByDayKey[AccountEvent.dayKey(for: date)]
    }

    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }

    func forceRefreshRates() async {}
}

@Suite("AccountsTotalsService")
struct AccountsTotalsServiceTests {

    private func makeContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    private func day(_ offset: Int, base: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Date {
        base.addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    // MARK: - AC13-ядро: seriesBetween использует курс СВОЕЙ даты, не сегодняшний

    @Test @MainActor
    func seriesBetweenUsesRateOfOwnDateNotToday() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        rateService.todayRate = 110
        rateService.historicalRatesByDayKey[AccountEvent.dayKey(for: day(0))] = 90
        rateService.historicalRatesByDayKey[AccountEvent.dayKey(for: day(1))] = 100

        _ = try service.createAccount(name: "Счёт USD", kind: .bankAccount, currency: "USD", openingBalance: 100, date: day(0))
        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)

        let series = await totals.seriesBetween(start: day(0), end: day(1), currency: "RUB")
        #expect(series.count == 2)
        #expect(series[0].1 == 9000)   // 100 × 90
        #expect(series[1].1 == 10_000) // 100 × 100, НЕ 100 × 110 (сегодняшний курс)
    }

    @Test @MainActor
    func totalAtSumsMultipleAccountsInTargetCurrency() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        rateService.todayRate = 100 // 1 USD = 100 RUB для простоты

        _ = try service.createAccount(name: "Карта RUB", kind: .cash, currency: "RUB", openingBalance: 5000)
        _ = try service.createAccount(name: "Счёт USD", kind: .bankAccount, currency: "USD", openingBalance: 10)

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let total = await totals.totalAt(Date(), in: "RUB")
        #expect(total == 6000) // 5000 + 10×100
    }

    @Test @MainActor
    func membershipEditRemovesAccountFromCurrentAndHistoricalTotals() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let core = AccountsCoreService(modelContext: ctx)
        let openedAt = day(-2)
        let account = try core.createAccount(
            name: "Квартира",
            kind: .manualAsset,
            currency: "RUB",
            openingBalance: 54_000_000,
            date: openedAt
        )
        let totals = AccountsTotalsService(
            modelContext: ctx,
            rebuilder: AccountSnapshotRebuilder(modelContainer: container),
            rateService: DateAwareMockRateService()
        )
        #expect(await totals.totalAt(Date(), in: "RUB") == 54_000_000)

        try core.updateAccount(
            account,
            name: account.name,
            group: nil,
            includeInTotal: false
        )

        #expect(await totals.totalAt(Date(), in: "RUB") == 0)
        #expect(await totals.totalAt(day(-1), in: "RUB") == 0)
    }

    @Test @MainActor
    func coreHistoricalTotalUsesPersistedRateBeforeProvider() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        let date = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        )
        rateService.historicalRatesByDayKey[AccountEvent.dayKey(for: date)] = 95

        _ = try service.createAccount(
            name: "Core USD", kind: .bankAccount, currency: "USD",
            openingBalance: 100, date: date.addingTimeInterval(-86_400)
        )
        ctx.insert(HistoricalRate(
            baseCurrency: "USD", quoteCurrency: "RUB", rate: 90,
            rateDate: date, source: "historical|tz=\(TimeZone.current.identifier)"
        ))
        try ctx.save()

        let totals = AccountsTotalsService(
            modelContext: ctx, rebuilder: rebuilder, rateService: rateService
        )
        let total = await totals.totalAt(date.addingTimeInterval(12 * 3_600), in: "RUB")

        #expect(total == 9_000)
        #expect(rateService.historicalCallCount == 0)
    }

    /// Phase 0 / AC-A1: точная синтетическая фикстура фиксирует текущую ошибку:
    /// при переходе той же модели данных из open-day в historical branch валютный
    /// вклад 22 507 974 молча исчезает. Это characterization; Phase 4 должна заменить
    /// голый Decimal на structured incomplete/closed result.
    @Test @MainActor
    func missingHistoricalFXReproducesExactNightJumpFixture() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        rateService.todayRate = 1

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let openedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        _ = try service.createAccount(
            name: "Resolved base", kind: .bankAccount, currency: "RUB",
            openingBalance: 77_125_067, date: openedAt
        )
        _ = try service.createAccount(
            name: "Foreign contribution", kind: .bankAccount, currency: "USD",
            openingBalance: 22_507_974, date: openedAt
        )

        let totals = AccountsTotalsService(
            modelContext: ctx, rebuilder: rebuilder, rateService: rateService
        )
        let openDayTotal = await totals.totalAt(Date(), in: "RUB")
        let historicalTotal = await totals.totalAt(yesterday, in: "RUB")

        #expect(openDayTotal == 99_633_041)
        #expect(historicalTotal == 77_125_067)
        #expect(openDayTotal - historicalTotal == 22_507_974)
    }

    /// Phase 1V / AC-D2: day-only checkpoint не может описать effective timestamp,
    /// поэтом earlier-same-day запрос обязан совпадать с direct replay.
    @Test @MainActor
    func snapshotBackedEarlierSameDayQueryEqualsDirectReplay() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayStart = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00 UTC
        let openingAt = calendar.date(byAdding: .hour, value: 9, to: dayStart)!
        let incomeAt = calendar.date(byAdding: .hour, value: 18, to: dayStart)!
        let noon = calendar.date(byAdding: .hour, value: 12, to: dayStart)!

        let account = try service.createAccount(
            name: "Same-day checkpoint", kind: .cash, currency: "RUB",
            openingBalance: 100, date: openingAt
        )
        try service.recordEvent(account: account, type: .income, amount: 50, date: incomeAt)
        try await rebuilder.rebuildAll(accountID: account.persistentModelID)

        let direct = AccountBalanceEngine.balanceAt(
            events: account.events ?? [], kind: account.kind, on: noon
        )
        let totals = AccountsTotalsService(
            modelContext: ctx, rebuilder: rebuilder, rateService: rateService
        )
        let snapshotBacked = await totals.totalAt(noon, in: "RUB")

        #expect(direct == 100)
        #expect(snapshotBacked == direct)
    }

    /// Phase 1V / AC-D2: persisted dayKey belongs to the timezone in which the event was created.
    /// A lexical "previous day" comparison in the current device timezone cannot prove that a
    /// checkpoint precedes the requested instant, so the compatibility reader must replay timestamps.
    @Test @MainActor
    func legacyTotalAtIgnoresCrossTimezoneLexicalSnapshot() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        let istanbul = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "Europe/Istanbul"))
        let losAngeles = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "America/Los_Angeles"))
        let instant = Date(timeIntervalSince1970: 1_704_157_200) // 2024-01-02 01:00 UTC
        let eventDate = instant.addingTimeInterval(-1_800)
        let query = instant.addingTimeInterval(1_800)
        #expect(istanbul.dayKey(for: query) == "2024-01-02")
        #expect(losAngeles.dayKey(for: query) == "2024-01-01")

        let account = Account(name: "Cross TZ", kind: .cash, currency: "RUB", createdAt: eventDate)
        let event = AccountEvent(account: account, date: eventDate, type: .openingBalance, amount: 100)
        event.dayKey = "2024-01-01" // frozen Los Angeles day from persisted source data
        let incompatible = AccountDailySnapshot(
            account: account, dayKey: "2024-01-01", balance: 999, isClosed: false
        )
        ctx.insert(account)
        ctx.insert(event)
        ctx.insert(incompatible)
        try ctx.save()

        let totals = AccountsTotalsService(
            modelContext: ctx, rebuilder: rebuilder, rateService: rateService
        )
        let result = await totals.totalAt(query, in: "RUB")

        #expect(result == 100)
    }

    /// A native-balance snapshot for day 1 embeds day-1 market evidence. Reusing it on day 3
    /// freezes the wrong price even when the day-3 price exists, so legacy totalAt also replays.
    @Test @MainActor
    func legacyTotalAtReplaysMarketAccountAtLaterDayPrice() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        let day1 = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00 UTC
        let day3 = day1.addingTimeInterval(2 * 86_400)

        let account = try service.createAccount(
            name: "TEST", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "TEST", assetClass: .stock), date: day1
        )
        try service.buy(account: account, quantity: 10, unitPrice: 50, date: day1)
        ctx.insert(AccountDailySnapshot(
            account: account,
            dayKey: AccountEvent.dayKey(for: day1),
            balance: 1_000,
            isClosed: false
        ))
        ctx.insert(HistoricalAssetPrice(
            symbol: "TEST", assetClass: .stock,
            dayKey: AccountEvent.dayKey(for: day1), price: 100, source: "test"
        ))
        ctx.insert(HistoricalAssetPrice(
            symbol: "TEST", assetClass: .stock,
            dayKey: AccountEvent.dayKey(for: day3), price: 300, source: "test"
        ))
        try ctx.save()

        let totals = AccountsTotalsService(
            modelContext: ctx,
            rebuilder: rebuilder,
            rateService: rateService,
            marketPriceService: AccountMarketPriceService(modelContext: ctx)
        )
        let result = await totals.totalAt(day3, in: "USD")

        #expect(result == 3_000)
    }

    /// Архивированный счёт не участвует в тотале «сегодня», но участвует в точке ДО архивации (AC6).
    @Test @MainActor
    func totalAtRespectsTimeAwareArchival() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()

        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 1000, date: day(0))
        let archivedAt = day(5)
        try service.archiveAccount(account, on: archivedAt)

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let beforeArchival = await totals.totalAt(day(3), in: "RUB")
        let afterArchival = await totals.totalAt(day(6), in: "RUB")
        #expect(beforeArchival == 1000)
        #expect(afterArchival == 0)
    }

    // MARK: - Фаза 2, брифинг п.4: тотал и знак — кредит входит отрицательным

    @Test @MainActor
    func totalAtIncludesLoanAsNegativeContribution() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()

        // openingBalance для .loan — МАГНИТУДА (движок C сам вычитает через loanSignMap), не итоговый
        // знак — см. регрессию, найденную и исправленную в AccountsCoreSeeder (Фаза 2).
        _ = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 5000)
        _ = try service.createAccount(name: "Кредит", kind: .loan, currency: "RUB", openingBalance: 2000)

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let total = await totals.totalAt(Date(), in: "RUB")
        #expect(total == 3000) // 5000 − 2000, тотал МЕНЬШЕ ровно на сумму кредита
    }

    // MARK: - Ф7b: core-кредитная карта входит в тотал как −долг, дебетовая — без изменений

    /// Кредитка нового create-пути: `.debitCard` + `openingBalance = остаток лимита` + `cardMeta.creditLimit`.
    /// Раньше уходила в тотал как +остаток (баг Ф7b); теперь — как −долг через единую точку знака.
    @Test @MainActor
    func totalAtIncludesCreditCardAsNegativeDebtContribution() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()

        // Дебетовая карта +5000 (creditLimit == nil) — контроль, что она не меняется.
        _ = try service.createAccount(name: "Дебет", kind: .debitCard, currency: "RUB", openingBalance: 5000)
        // Кредитка: остаток лимита 1 374 000, лимит 1 500 000 → долг 126 000.
        _ = try service.createAccount(
            name: "Кредитка", kind: .debitCard, currency: "RUB", openingBalance: 1_374_000,
            cardMeta: CardMeta(bank: nil, last4: nil, creditLimit: 1_500_000, statementDay: nil,
                               dueDay: nil, minPayment: nil, graceDays: nil, overdraftLimit: nil)
        )

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let total = await totals.totalAt(Date(), in: "RUB")
        #expect(total == -121_000) // 5000 (дебет) − 126_000 (долг кредитки)
    }

    /// Ф7b-2 (репро девайс-бага): ПОЛНЫЙ путь создания кредитки формой «Новый продукт» БЕЗ выбранного
    /// банка. Форма даёт kind через `AccountsCoreAdditionBridge.cardKind(bank: .other) == .cash`,
    /// openingBalance = max(0, лимит − долг), cardMeta.creditLimit = лимит. До фикса тотал давал
    /// +остаток (знак терялся на гарде `.debitCard`); теперь — −долг. Одновременно проверяем, что
    /// лимит НЕ теряется по пути создания (сохранён в cardMeta).
    @Test @MainActor
    func creditCardCreatedWithoutBankViaFormPathContributesNegativeDebt() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()

        // Тот же расчёт, что делает InlineCardDraft.currentCard для cardType == .credit:
        let limit: Decimal = 1_500_000
        let debt: Decimal = 200_000
        let openingBalance = max(0, limit - debt) // 1 300 000 (остаток лимита)

        // kind — ровно как выводит форма для карты без банка (bank == .other):
        let kind = AccountsCoreAdditionBridge.cardKind(bank: .other)
        #expect(kind == .cash) // фиксируем предпосылку бага: кредитка без банка → .cash

        let cardMeta = CardMeta(bank: nil, last4: nil, creditLimit: limit, statementDay: nil,
                                dueDay: nil, minPayment: nil, graceDays: nil, overdraftLimit: nil)
        let account = try service.createAccount(
            name: "Кредитка без банка", kind: kind, currency: "RUB",
            openingBalance: openingBalance, cardMeta: cardMeta
        )

        // Лимит не потерян по пути создания.
        #expect(account.cardMeta?.creditLimit == limit)

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let total = await totals.totalAt(Date(), in: "RUB")
        #expect(total == -debt) // −200 000, а не +1 300 000
    }

    /// AC7/AC6: архивный `.loan` без группы (Ungrouped) не «утекает» в сегодняшний тотал —
    /// его отрицательный вклад исчезает с даты архивации, но история ДО неё не меняется задним числом.
    @Test @MainActor
    func archivedUngroupedLoanDoesNotLeakIntoTodayTotalButRemainsInPastTotal() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()

        let loan = try service.createAccount(name: "Кредит", kind: .loan, currency: "RUB", openingBalance: 2000, date: day(0))
        #expect(loan.group == nil) // Ungrouped по умолчанию
        let archivedAt = day(5)
        try service.archiveAccount(loan, on: archivedAt)

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let beforeArchival = await totals.totalAt(day(3), in: "RUB")
        let afterArchival = await totals.totalAt(day(6), in: "RUB")
        #expect(beforeArchival == -2000) // история не переписана — кредит виден со своим минусом
        #expect(afterArchival == 0)      // «сегодня» (после архивации) — не участвует, минус не утекает
    }

    // MARK: - Т2: compatibility performance smoke for same-day direct replay

    @Test @MainActor
    func totalAtSameDayReplayCompletesWithinCompatibilityBudget() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()

        let accountsCount = 5
        let eventsPerAccount = 1000 // 5 × 1000 = 5 000 событий, ~2.7 года при шаге в день
        var accounts: [Account] = []
        for index in 0..<accountsCount {
            let account = try service.createAccount(
                name: "Счёт \(index)", kind: .cash, currency: "RUB", openingBalance: 1000, date: day(0)
            )
            for step in 1..<eventsPerAccount {
                let type: AccountEventType = step.isMultiple(of: 2) ? .income : .expense
                try service.recordEvent(account: account, type: type, amount: 10, date: day(step))
            }
            accounts.append(account)
        }
        try ctx.save()

        // Rebuild remains part of the compatibility path, but a day-only checkpoint cannot answer
        // an arbitrary timestamp inside its own day. The measured call therefore includes direct
        // replay and this is deliberately a coarse regression budget, not an O(1) cache claim.
        let lastDay = day(eventsPerAccount - 1)
        for account in accounts {
            try await rebuilder.rebuildAll(accountID: account.persistentModelID)
        }

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let started = ContinuousClock.now
        _ = await totals.totalAt(lastDay, in: "RUB")
        let elapsed = started.duration(to: .now)

        // The 2s threshold absorbs simulator contention. It does not promise constant-time replay.
        #expect(elapsed < .seconds(2), "totalAt(today) на тёплом кэше занял \(elapsed) — ожидали < 2с")
    }

    // MARK: - Фаза 4: реальный MarketPriceProviding подключён к totalAt/seriesBetween

    /// Прокладка провайдера (брифинг Фазы 4, задача 3): без `marketPriceService` — рыночный счёт
    /// считается по lastKnown buy-цене (fallback внутри движка E), не выпадает из тотала.
    @Test @MainActor
    func totalAtFallsBackToLastKnownPriceWithoutMarketPriceService() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        rateService.todayRate = 1

        let account = try service.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        try service.buy(account: account, quantity: 10, unitPrice: 100)

        // marketPriceService НЕ передан — обратная совместимость с Фазой 1a.
        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let total = await totals.totalAt(Date(), in: "USD")
        #expect(total == 1000) // 10 × 100 (lastKnown buy-цена), счёт участвует в тотале
    }

    /// С подключённым `AccountMarketPriceService` тотал использует ЖИВУЮ кэшированную цену,
    /// а не last-known buy-цену (брифинг Фазы 4, задача 3 — интеграция провайдера в тотал).
    @Test @MainActor
    func totalAtUsesLiveCachedPriceWhenMarketPriceServiceIsWired() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        rateService.todayRate = 1

        let account = try service.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        try service.buy(account: account, quantity: 10, unitPrice: 100) // цена покупки — 100

        // В кэше уже есть СЕГОДНЯШНЯЯ живая цена 155 (симулируем предварительный refresh).
        let todayKey = AccountEvent.dayKey(for: Date())
        ctx.insert(HistoricalAssetPrice(symbol: "AAPL", assetClass: .stock, dayKey: todayKey, price: 155, source: "test"))
        try ctx.save()

        let marketPriceService = AccountMarketPriceService(modelContext: ctx)
        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService, marketPriceService: marketPriceService)
        let total = await totals.totalAt(Date(), in: "USD")
        #expect(total == 1550) // 10 × 155 (живая цена из кэша), НЕ 10 × 100 (цена покупки)
    }

    // MARK: - AC6 (Фаза 5, задача 1): архивация time-aware — история ДО archivedAt неизменна байт-в-байт

    /// Создаём счёт с историей → архивируем → точка ДО archivedAt (вчера) в `seriesBetween`
    /// совпадает С ТОЧНОСТЬЮ ДО Decimal (не приблизительно) с точкой ДО архивации; сегодняшняя
    /// точка счёт больше не включает; `restoreAccount` полностью обратим.
    @Test @MainActor
    func archivingAccountDoesNotChangeHistoricalPointsButExcludesToday() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        rateService.todayRate = 1

        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 1000, date: day(0))
        try service.recordEvent(account: account, type: .income, amount: 500, date: day(1))
        try ctx.save()

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)

        let seriesBeforeArchive = await totals.seriesBetween(start: day(0), end: day(2), currency: "RUB")
        #expect(seriesBeforeArchive.map(\.1) == [1000, 1500, 1500])

        // Архивируем РОВНО на day(2) — граница строгая (date < archivedAt), сама точка day(2) уже не участвует.
        try service.archiveAccount(account, on: day(2))

        let seriesAfterArchive = await totals.seriesBetween(start: day(0), end: day(2), currency: "RUB")
        // Байт-в-байт: точки ДО archivedAt идентичны ДО и ПОСЛЕ архивации (не «примерно похожи»).
        #expect(seriesAfterArchive[0].1 == seriesBeforeArchive[0].1) // day(0): 1000 == 1000
        #expect(seriesAfterArchive[1].1 == seriesBeforeArchive[1].1) // day(1): 1500 == 1500
        #expect(seriesAfterArchive[2].1 == 0) // day(2) == archivedAt → не участвует, "обнуление с сегодня"

        // "Сегодня" (реальное текущее время, далеко после day(2)) счёт тоже не участвует.
        let totalToday = await totals.totalAt(Date(), in: "RUB")
        #expect(totalToday == 0)

        // Обратимость: после restore точка day(2) и "сегодня" снова включают счёт.
        try service.restoreAccount(account)
        let seriesAfterRestore = await totals.seriesBetween(start: day(0), end: day(2), currency: "RUB")
        #expect(seriesAfterRestore.map(\.1) == seriesBeforeArchive.map(\.1))
        let totalTodayAfterRestore = await totals.totalAt(Date(), in: "RUB")
        #expect(totalTodayAfterRestore == 1500)
    }
}
