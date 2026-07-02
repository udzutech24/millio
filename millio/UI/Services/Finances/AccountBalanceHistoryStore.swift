//
//  AccountBalanceHistoryStore.swift
//  millio
//
//  Хранит ежедневные снапшоты баланса по каждому счёту.
//  Файл: Application Support / account_balance_history_v1.json
//  Объём: до 365 дней × N счетов. Старые записи удаляются автоматически.
//

import Foundation

enum AccountBalanceHistoryStore {

    // MARK: - Константы

    private static let maxDays = 365
    private static let fileName = "account_balance_history_v1.json"

    // MARK: - Типы

    struct Record: Codable {
        let dateKey: String   // "2026-06-13"
        let amount: Double
        let currency: String
    }

    // Весь файл: accountID → [Record]
    typealias Storage = [String: [Record]]

    // MARK: - Public API

    /// Сохраняет баланс счёта за сегодня. Вызывается из AccountBalanceSnapshotService.
    static func save(accountID: String, amount: Double, currency: String, for date: Date = Date()) {
        guard amount.isFinite else { return }
        var storage = load()
        var records = storage[accountID] ?? []
        let dk = dayKey(for: date)
        records.removeAll { $0.dateKey == dk }
        records.append(Record(dateKey: dk, amount: amount, currency: currency))
        let trimmed = Array(records.sorted { $0.dateKey < $1.dateKey }.suffix(maxDays))
        storage[accountID] = trimmed
        save(storage)
    }

    /// Возвращает [oldest … today] за `daysCount` дней для одного счёта.
    /// nil в позиции — данных за этот день нет.
    static func dailyAmounts(
        accountID: String,
        currency: String,
        daysCount: Int,
        referenceDate: Date = Date()
    ) -> [Double?] {
        let records = (load()[accountID] ?? []).filter { $0.currency == currency }
        let byKey = Dictionary(uniqueKeysWithValues: records.map { ($0.dateKey, $0.amount) })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        return (0..<daysCount).reversed().map { offset -> Double? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byKey[dayKey(for: date)]
        }
    }

    /// Количество точек с данными для счёта.
    static func recordCount(accountID: String, currency: String) -> Int {
        (load()[accountID] ?? []).filter { $0.currency == currency }.count
    }

    /// Сырые данные для одноразовой миграции в SwiftData daily snapshots.
    static func loadRaw() -> Storage {
        load()
    }

    /// Архивирует старый JSON после успешной миграции. Не удаляем файл сразу:
    /// это страховка на случай сбоя новой схемы у пользователя.
    static func renameToMigrated() {
        guard let url = fileURL else { return }
        let migratedURL = url.deletingPathExtension().appendingPathExtension("migrated")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: migratedURL)
        try? FileManager.default.moveItem(at: url, to: migratedURL)
    }

    /// Исторические данные нельзя чистить по списку активных счетов:
    /// архивный/удалённый счёт всё ещё участник закрытой истории.
    static func cleanup(keepingIDs activeIDs: Set<String>) {
        assertionFailure("AccountBalanceHistoryStore.cleanup запрещён: daily snapshots являются immutable history")
        AppLogger.log(.warning, category: "Finance", "Ignored AccountBalanceHistoryStore.cleanup for \(activeIDs.count) active IDs")
    }

    // MARK: - Private

    private static func load() -> Storage {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Storage.self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ storage: Storage) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(storage)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }

    static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
