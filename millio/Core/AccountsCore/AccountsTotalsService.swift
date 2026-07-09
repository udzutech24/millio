import Foundation
import SwiftData

/// Единая точка расчёта тоталов/графика по счетам нового ядра — заменяет три расходящихся пути
/// старого мира (AC2: Accounts-тотал == Analytics-тотал == график). НЕ трогает старый
/// `FinanceTotalsService` (интеграция сумм old+new — задача Фазы 1a-ui).
@MainActor
final class AccountsTotalsService {
    private let modelContext: ModelContext
    private let rebuilder: AccountSnapshotRebuilder
    private let rateService: CurrencyRateServiceProtocol
    /// Опционален (Фаза 4): без него рыночные счета считаются по последней известной цене buy/sell
    /// из событий (fallback внутри `AccountBalanceEngine.marketBalance`) — тесты, не подключающие
    /// живые котировки, продолжают работать без изменений (обратная совместимость с Фазой 1a).
    private let marketPriceService: AccountMarketPriceService?

    init(
        modelContext: ModelContext,
        rebuilder: AccountSnapshotRebuilder,
        rateService: CurrencyRateServiceProtocol,
        marketPriceService: AccountMarketPriceService? = nil
    ) {
        self.modelContext = modelContext
        self.rebuilder = rebuilder
        self.rateService = rateService
        self.marketPriceService = marketPriceService
    }

    /// Быстрая проверка «есть ли хоть один счёт нового ядра» — дешёвый COUNT без загрузки объектов.
    /// Все дорогие пути (`totalAt`/`seriesBetween`) выходят рано, пока новых счетов ещё нет
    /// (Т2 в плане: не платим за реплей там, где платить не за что — критично для сосуществования
    /// со старым миром в Фазе 1a-ui, где у подавляющего большинства ViewModel'ов новых счетов нет).
    private func hasAnyAccounts() -> Bool {
        ((try? modelContext.fetchCount(FetchDescriptor<Account>())) ?? 0) > 0
    }

    /// Σ по счетам нового ядра: `balanceAt(счёт, date)` в валюте счёта × курс(валюта счёта → currency,
    /// НА ДАТУ `date`). Для сегодня — текущий курс, для прошлого — исторический (AC13).
    func totalAt(_ date: Date, in currency: String, participatingOnly: Bool = true) async -> Decimal {
        guard hasAnyAccounts(), let accounts = try? modelContext.fetch(FetchDescriptor<Account>()) else { return 0 }

        // Провайдер цен строится ОДИН РАЗ на весь вызов (не на каждый счёт) — одна выборка кэша на
        // все символы портфеля вместо N (Т2: не платим за реплей там, где можно один раз прочитать кэш).
        let priceProvider = marketPriceProvider(for: accounts)

        var total: Decimal = 0
        for account in accounts {
            if participatingOnly, !account.participates(on: date) { continue }
            guard let balance = try? await balance(for: account, on: date, priceProvider: priceProvider) else { continue }
            guard balance != 0 else { continue } // 0 × курс = 0 — не запрашиваем курс впустую
            guard let rate = await rate(from: account.currency, to: currency, on: date) else { continue }
            total += balance * Decimal(rate)
        }
        return total
    }

    /// Σ по ЗАДАННОМУ подмножеству счетов нового ядра на дату — та же механика, что `totalAt`, но по
    /// готовому списку (per-group сумма: Фаза 1.5 слияния групп, чтобы группа из core-счетов давала
    /// верную сумму/дельту на экранах «Счета»/«Динамика»). `participatingOnly` фильтрует архивные.
    func total(for accounts: [Account], on date: Date, in currency: String, participatingOnly: Bool = true) async -> Decimal {
        guard !accounts.isEmpty else { return 0 }
        let priceProvider = marketPriceProvider(for: accounts)
        var total: Decimal = 0
        for account in accounts {
            if participatingOnly, !account.participates(on: date) { continue }
            guard let balance = try? await balance(for: account, on: date, priceProvider: priceProvider) else { continue }
            guard balance != 0 else { continue }
            guard let rate = await rate(from: account.currency, to: currency, on: date) else { continue }
            total += balance * Decimal(rate)
        }
        return total
    }

    /// Точки для графика: одна точка на календарный день между `start` и `end` включительно,
    /// каждая — курсом СВОЕЙ даты (AC13), не сегодняшним.
    func seriesBetween(start: Date, end: Date, currency: String) async -> [(Date, Decimal)] {
        guard start <= end, hasAnyAccounts() else { return [] }
        var result: [(Date, Decimal)] = []
        var cursor = start
        let calendar = Calendar(identifier: .gregorian)
        while cursor <= end {
            let value = await totalAt(cursor, in: currency)
            result.append((cursor, value))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    // MARK: - Баланс счёта на дату (кэш с fallback на реплей)

    private func balance(for account: Account, on date: Date, priceProvider: MarketPriceProviding?) async throws -> Decimal {
        // Досчитываем недостающий хвост кэша (быстрый no-op на тёплом кэше — Т2).
        try await rebuilder.rebuild(accountID: account.persistentModelID, upTo: date, priceProvider: priceProvider)

        // ВАЖНО: снапшоты вставляет фоновый актор через СВОЙ ModelContext (свой контейнер того же
        // хранилища). Кэшированная relationship `account.snapshots` в НАШЕМ mainContext эту вставку
        // не увидит без явного refetch — читаем `AccountDailySnapshot` прямым запросом (S4/cross-context).
        let accountRecordID = account.id
        let dayKey = AccountEvent.dayKey(for: date)
        var descriptor = FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { $0.account?.id == accountRecordID && $0.dayKey <= dayKey }
        )
        descriptor.sortBy = [SortDescriptor(\.dayKey, order: .reverse)]
        descriptor.fetchLimit = 1

        if let snapshot = try? modelContext.fetch(descriptor).first {
            return snapshot.balance
        }

        // Нет ни одного checkpoint-а ≤ date (счёт создан позже date, либо событий вовсе нет) — прямой реплей.
        return AccountBalanceEngine.balanceAt(
            events: account.events ?? [],
            kind: account.kind,
            on: date,
            priceProvider: priceProvider,
            marketMeta: account.marketMeta
        )
    }

    // MARK: - Провайдер цен (Фаза 4)

    /// Собирает `MarketPriceProviding` ОДИН РАЗ на список счетов — единственная выборка кэша цен
    /// на все символы, а не по одной на каждый рыночный счёт (Т2). `nil`, если сервис не подключён
    /// (совместимость с вызовами Фазы 1a/тестами) или в выборке нет рыночных счетов.
    private func marketPriceProvider(for accounts: [Account]) -> MarketPriceProviding? {
        guard let marketPriceService else { return nil }
        let symbols = accounts.compactMap { $0.kind == .marketInvestment ? $0.marketMeta?.symbol : nil }
        guard !symbols.isEmpty else { return nil }
        return marketPriceService.makeSnapshotProvider(symbols: symbols)
    }

    // MARK: - Курс на дату

    private func rate(from: String, to: String, on date: Date) async -> Double? {
        if from.uppercased() == to.uppercased() { return 1 }
        if Calendar.current.isDateInToday(date) {
            return await rateService.getRate(from: from, to: to)
        }
        return await rateService.getHistoricalRate(on: date, from: from, to: to)
    }
}
