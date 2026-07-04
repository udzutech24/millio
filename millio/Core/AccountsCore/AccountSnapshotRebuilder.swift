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
    func rebuild(accountID: PersistentIdentifier, upTo: Date) throws {
        guard let account = modelContext.model(for: accountID) as? Account else { return }
        try rebuildCheckpoints(for: account, upTo: upTo, keepExisting: true)
    }

    /// Полная пересборка «с нуля»: удаляет все снапшоты счёта и реплеит заново по всем дням событий.
    /// Результат идентичен прямому реплею на любую дату (AC8) — используется тестом и для
    /// разового «Пересобрать кэш» без миграции старых данных.
    func rebuildAll(accountID: PersistentIdentifier) throws {
        guard let account = modelContext.model(for: accountID) as? Account else { return }
        for snapshot in account.snapshots ?? [] {
            modelContext.delete(snapshot)
        }
        try modelContext.save()
        try rebuildCheckpoints(for: account, upTo: .distantFuture, keepExisting: false)
    }

    // MARK: - Внутренняя пересборка

    private func rebuildCheckpoints(for account: Account, upTo: Date, keepExisting: Bool) throws {
        let upToKey = AccountEvent.dayKey(for: upTo)
        let existing = account.snapshots ?? []
        // Последний ОСТАВШИЙСЯ снапшот — граница, до которой кэш валиден и трогать не нужно.
        let lastValidKey = keepExisting ? (existing.map(\.dayKey).max() ?? "") : ""

        // Т2: быстрый выход БЕЗ обращения к `account.events` — на тёплом кэше (снапшот уже
        // покрывает запрошенную дату) не сканируем всю историю событий на каждый вызов totalAt.
        guard keepExisting == false || lastValidKey < upToKey else { return }

        let events = account.events ?? []
        guard !events.isEmpty else { return }

        let dayKeysToBuild = Set(events.map(\.dayKey))
            .filter { $0 > lastValidKey && $0 <= upToKey }
            .sorted()

        guard !dayKeysToBuild.isEmpty else { return }

        var byKey: [String: AccountDailySnapshot] = [:]
        for snapshot in existing { byKey[snapshot.dayKey] = snapshot }

        for dayKey in dayKeysToBuild {
            // Курсор дня = дата ПОСЛЕДНЕГО события этого dayKey — гарантирует, что balanceAt(≤cursor)
            // включает все события дня независимо от разброса времени внутри дня (события с одним
            // dayKey группируются по локальному календарю на момент создания, см. AccountEvent.dayKey).
            guard let cursor = events.filter({ $0.dayKey == dayKey }).map(\.date).max() else { continue }

            let balance = AccountBalanceEngine.balanceAt(
                events: events,
                kind: account.kind,
                on: cursor,
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

        try modelContext.save()
    }
}
