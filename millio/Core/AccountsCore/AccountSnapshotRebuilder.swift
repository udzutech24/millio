import Foundation
import SwiftData

/// Фоновая пересборка снапшот-кэша `AccountDailySnapshot` из событий (S4: НЕ MainActor —
/// реплей длинной истории не должен блокировать UI-поток).
///
/// Кэш «разреженный»: точка кладётся только на дни, где реально было хотя бы одно событие
/// (checkpoint-дни) — между checkpoint-ами баланс по определению не меняется (нет событий),
/// поэтому запрос произвольной даты обслуживается ближайшим checkpoint-ом «≤ дата» без потери
/// точности и без раздувания таблицы на пустые календарные дни (KISS, AC8).
@ModelActor
actor AccountSnapshotRebuilder {

    /// Инкрементально пересобирает кэш счёта: досчитывает checkpoint-ы для всех дней событий,
    /// оставшихся ПОСЛЕ последнего сохранившегося снапшота, вплоть до дня `upTo` включительно.
    /// Уже существующие снапшоты (валидные — их не тронула инвалидация) не пересчитываются.
    /// `priceProvider` — только для `.marketInvestment` (Фаза 4, S4: `Sendable`-снэпшот кэша цен,
    /// собранный ВНЕ этого актора синхронным чтением `AccountMarketPriceService.makeSnapshotProvider`).
    func rebuild(accountID: PersistentIdentifier, upTo: Date, priceProvider: MarketPriceProviding? = nil) throws {
        guard let account = modelContext.model(for: accountID) as? Account else { return }
        try rebuildCheckpoints(for: account, upTo: upTo, keepExisting: true, priceProvider: priceProvider)
    }

    /// Полная пересборка «с нуля»: удаляет все снапшоты счёта и реплеит заново по всем дням событий.
    /// Результат идентичен прямому реплею на любую дату (AC8) — используется тестом и для
    /// разового «Пересобрать кэш» без миграции старых данных.
    func rebuildAll(accountID: PersistentIdentifier, priceProvider: MarketPriceProviding? = nil) throws {
        guard let account = modelContext.model(for: accountID) as? Account else { return }
        for snapshot in try snapshots(for: account.id) {
            modelContext.delete(snapshot)
        }
        try modelContext.save()
        try rebuildCheckpoints(for: account, upTo: .distantFuture, keepExisting: false, priceProvider: priceProvider)
    }

    /// Разовая пересборка кэша ВСЕХ счетов нового ядра (задача 6/Фаза 5, AC8 debug-ручка) — для
    /// восстановления консистентности после ручного вмешательства в БД или подозрения на
    /// рассинхронизацию кэша. Возвращает число обработанных счетов (для тоста в UI).
    @discardableResult
    func rebuildAllAccounts() throws -> Int {
        let accounts = try modelContext.fetch(FetchDescriptor<Account>())
        for account in accounts {
            try rebuildAll(accountID: account.persistentModelID)
        }
        return accounts.count
    }

    // MARK: - Внутренняя пересборка

    private func rebuildCheckpoints(for account: Account, upTo: Date, keepExisting: Bool, priceProvider: MarketPriceProviding?) throws {
        let upToKey = AccountEvent.dayKey(for: upTo)
        var existing = try snapshots(for: account.id)

        // Архивный счёт (задача 4/Фаза 5): снапшоты СТРОГО ПОСЛЕ дня закрытия не имеют права
        // существовать — история после archivedAt не участвует в тоталах (participates(on:)),
        // поэтому кэшу нечего там хранить. Чистим хвост даже если он остался от rebuild ДО архивации.
        let archivedDayKey = account.archivedAt.map { AccountEvent.dayKey(for: $0) }
        if let archivedDayKey {
            let staleAfterArchive = existing.filter { $0.dayKey > archivedDayKey }
            if !staleAfterArchive.isEmpty {
                for snapshot in staleAfterArchive { modelContext.delete(snapshot) }
                existing.removeAll { $0.dayKey > archivedDayKey }
            }
        }

        // Последний ОСТАВШИЙСЯ снапшот — граница, до которой кэш валиден и трогать не нужно.
        let lastValidKey = keepExisting ? (existing.map(\.dayKey).max() ?? "") : ""

        // Т2: быстрый выход БЕЗ обращения к `account.events` — на тёплом кэше (снапшот уже
        // покрывает запрошенную дату) не сканируем всю историю событий на каждый вызов totalAt.
        guard keepExisting == false || lastValidKey < upToKey else {
            if archivedDayKey != nil { try modelContext.save() } // сохранить чистку хвоста выше
            return
        }

        let events = try events(for: account.id)
        guard !events.isEmpty else {
            if archivedDayKey != nil { try modelContext.save() }
            return
        }

        let dayKeysToBuild = Set(events.map(\.dayKey))
            .filter { $0 > lastValidKey && $0 <= upToKey }
            // Не строим checkpoint-ы позже дня закрытия — счёт больше не участвует (AC6/AC7, задача 4).
            .filter { archivedDayKey == nil || $0 <= archivedDayKey! }
            .sorted()

        guard !dayKeysToBuild.isEmpty else {
            if archivedDayKey != nil { try modelContext.save() }
            return
        }

        var byKey: [String: AccountDailySnapshot] = [:]
        for snapshot in existing { byKey[snapshot.dayKey] = snapshot }

        // Батчинг сохранений (задача snapshot-backfill: 5-летняя история ≈ 1800 checkpoint-ов на счёт).
        // Без промежуточных save() большая пересборка — ОДНА SwiftData-транзакция целиком: уход
        // приложения в бэкграунд/снятие системой посреди реплея откатывает ВСЮ проделанную работу,
        // и следующий запуск стартует с нуля заново. Периодический save() каждые `saveBatchSize`
        // обработанных дней делает частичный прогресс валидным — повторный вызов просто продолжит
        // с последнего РЕАЛЬНО сохранённого checkpoint-а (`lastValidKey` выше пересчитывается с диска).
        // `autoreleasepool` — тот же цикл строит `Decimal`/`Date` на каждой итерации; без периодического
        // дренажа промежуточные объекты живут до конца всего вызова вместо конца пачки.
        var processedSinceSave = 0

        for dayKey in dayKeysToBuild {
            // Курсор дня = дата ПОСЛЕДНЕГО события этого dayKey — гарантирует, что balanceAt(≤cursor)
            // включает все события дня независимо от разброса времени внутри дня (события с одним
            // dayKey группируются по локальному календарю на момент создания, см. AccountEvent.dayKey).
            guard let cursor = events.filter({ $0.dayKey == dayKey }).map(\.date).max() else { continue }

            autoreleasepool {
                let balance = AccountBalanceEngine.balanceAt(
                    events: events,
                    kind: account.kind,
                    on: cursor,
                    priceProvider: priceProvider,
                    marketMeta: account.marketMeta
                )
                let isClosed = !account.participates(on: cursor)

                if let existingSnapshot = byKey[dayKey] {
                    existingSnapshot.balance = balance
                    existingSnapshot.isClosed = isClosed
                    existingSnapshot.updatedAt = Date()
                } else {
                    let snapshot = AccountDailySnapshot(account: account, dayKey: dayKey, balance: balance, isClosed: isClosed)
                    modelContext.insert(snapshot)
                }
            }

            processedSinceSave += 1
            if processedSinceSave >= Self.saveBatchSize {
                try modelContext.save()
                processedSinceSave = 0
            }
        }

        try modelContext.save()
    }

    /// Relationship-коллекции SwiftData могут быть fault-ами, привязанными к чужому контексту
    /// после параллельной записи или CloudKit merge. Фоновый `@ModelActor` читает только через
    /// собственный `modelContext`, чтобы не передавать lazy relationship между контекстами.
    private func snapshots(for accountID: UUID) throws -> [AccountDailySnapshot] {
        let descriptor = FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { $0.account?.id == accountID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func events(for accountID: UUID) throws -> [AccountEvent] {
        let descriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.account?.id == accountID },
            sortBy: [
                SortDescriptor(\AccountEvent.date),
                SortDescriptor(\AccountEvent.createdAt)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Размер пачки перед промежуточным `save()` при большой пересборке (см. комментарий выше).
    private static let saveBatchSize = 200
}
