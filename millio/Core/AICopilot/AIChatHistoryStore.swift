//
//  AIChatHistoryStore.swift
//  millio
//

import Foundation

/// История диалога на устройстве: сервер stateless и ничего не помнит.
///
/// Хранилище — `UserDefaults`, а не SwiftData, сознательно: новая `@Model` сдвигает checksum схемы
/// (известная ловушка с нечитаемыми сторами), а переписка не нужна ни в бэкапе, ни в CloudKit.
/// Объём ограничен сверху 20 ходами — это десятки килобайт.
final class AIChatHistoryStore {
    static let defaultStorageKey = "ai.chat.history.v1"

    private let defaults: UserDefaults
    private let storageKey: String
    private let capacity: Int

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = AIChatHistoryStore.defaultStorageKey,
        capacity: Int = AIChatPayloadBuilder.maxHistoryMessages
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.capacity = max(2, capacity)
    }

    /// Ключ на scope данных: в гостевом режиме переписка владельца не должна быть видна
    /// (та же природа, что у утечки бэкапов в гостя).
    static func storageKey(forScopeKey scopeKey: String) -> String {
        "\(defaultStorageKey).\(scopeKey)"
    }

    func load() -> [AIChatMessage] {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([AIChatMessage].self, from: data)
        else { return [] }
        return trimmed(decoded)
    }

    func save(_ messages: [AIChatMessage]) {
        let value = trimmed(messages)
        guard !value.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    /// Оставляем последние ходы и срезаем «висящий» ответ в начале: вопрос к нему уже выпал,
    /// и модель получила бы реплику без контекста.
    private func trimmed(_ messages: [AIChatMessage]) -> [AIChatMessage] {
        Array(messages.suffix(capacity).drop(while: { $0.role == .assistant }))
    }
}
