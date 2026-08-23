//
//  AutoRestoreAttemptCounter.swift
//  millio
//

import Foundation

/// Счётчик попыток автоматического restore при старте: после исчерпания лимита деструктивный
/// автоматический путь закрывается в пользу ручного экрана восстановления.
///
/// Счётчик намеренно глобальный (не per-scope) — семантика не менялась при выносе из `millioApp`,
/// см. R1/R7 плана recovery-rework.
struct AutoRestoreAttemptCounter {
    static let maxAttempts = 2
    static let storageKey = "autoRestoreAttemptCount"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var attempts: Int {
        defaults.integer(forKey: Self.storageKey)
    }

    var hasReachedLimit: Bool {
        attempts >= Self.maxAttempts
    }

    func registerAttempt() {
        defaults.set(attempts + 1, forKey: Self.storageKey)
    }

    /// Вызывается только на подтверждённом успехе restore — иначе лимит перестаёт защищать
    /// от бесконечного цикла «падение авто-restore → перезапуск».
    func reset() {
        defaults.set(0, forKey: Self.storageKey)
    }
}
