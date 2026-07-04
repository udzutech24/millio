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

    init(modelContext: ModelContext, rebuilder: AccountSnapshotRebuilder, rateService: CurrencyRateServiceProtocol) {
        self.modelContext = modelContext
        self.rebuilder = rebuilder
        self.rateService = rateService
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

        var total: Decimal = 0
        for account in accounts {
            if participatingOnly, !account.participates(on: date) { continue }
            guard let balance = try? await balance(for: account, on: date) else { continue }
            guard balance != 0 else { continue } // 0 × курс = 0 — не запрашиваем курс впустую
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

    private func balance(for account: Account, on date: Date) async throws -> Decimal {
        // Досчитываем недостающий хвост кэша (быстрый no-op на тёплом кэше — Т2).
        try await rebuilder.rebuild(accountID: account.persistentModelID, upTo: date)

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
        return AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: date)
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
