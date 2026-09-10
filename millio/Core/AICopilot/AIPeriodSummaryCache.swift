//
//  AIPeriodSummaryCache.swift
//  millio
//

import Foundation

/// Кэш формулировок по ключу «период + цифры». Те же цифры — тот же текст: показываем мгновенно
/// при следующем открытии и не тратим лимит эндпоинта (5 запросов в минуту).
final class AIPeriodSummaryCache {
    private struct Entry: Codable {
        let key: String
        let text: AIPeriodSummaryText
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let capacity: Int

    init(defaults: UserDefaults = .standard, storageKey: String = "ai.period_summary.cache.v1", capacity: Int = 8) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.capacity = max(1, capacity)
    }

    func text(forKey key: String) -> AIPeriodSummaryText? {
        entries().first { $0.key == key }?.text
    }

    func store(_ text: AIPeriodSummaryText, forKey key: String) {
        // Пустой текст не кэшируем: сервер вернул цифры без формулировки (Claude недоступен) —
        // при следующем открытии надо попробовать ещё раз, а не запомнить пустоту.
        guard !text.isEmpty else { return }
        var updated = entries().filter { $0.key != key }
        updated.insert(Entry(key: key, text: text), at: 0)
        if updated.count > capacity { updated = Array(updated.prefix(capacity)) }
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func entries() -> [Entry] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return decoded
    }
}
