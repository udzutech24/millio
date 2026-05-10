//
//  DashboardBalanceHistoryStore.swift
//  millio

import Foundation

/// Хранит ежедневные снапшоты общего баланса для построения sparkline на дашборде.
/// Запись происходит автоматически при каждом вызове calculateTotalAmountAsync().
enum DashboardBalanceHistoryStore {
    private static let key = "dashboard.balance.history.v1"
    private static let maxDays = 35

    struct Record: Codable {
        let dateKey: String   // "2026-05-09"
        let amount: Double
        let currency: String
    }

    /// Сохраняет баланс за указанный день (по умолчанию — сегодня).
    static func save(_ amount: Double, currency: String, for date: Date = Date()) {
        guard amount.isFinite else { return }
        var records = loadAll()
        let dk = dayKey(for: date)
        records.removeAll { $0.dateKey == dk }
        records.append(Record(dateKey: dk, amount: amount, currency: currency))
        let trimmed = Array(records.sorted { $0.dateKey < $1.dateKey }.suffix(maxDays))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Возвращает массив из `daysCount` элементов: [oldest … today].
    /// Элемент nil — данных за этот день нет.
    static func dailyAmounts(
        currency: String,
        daysCount: Int,
        referenceDate: Date = Date()
    ) -> [Double?] {
        let all = loadAll().filter { $0.currency == currency }
        let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.dateKey, $0.amount) })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        return (0..<daysCount).reversed().map { offset -> Double? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byKey[dayKey(for: date)]
        }
    }

    private static func loadAll() -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return decoded
    }

    private static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
