//
//  LaunchRecoveryStateStore.swift
//  millio
//

import Foundation

/// Персистентное состояние launch-recovery в `UserDefaults`: счётчик попыток автоматического
/// restore и отказ пользователя от восстановления.
///
/// Одна сущность на два факта намеренно: оба живут в `UserDefaults`, оба читаются/пишутся
/// ровно на пути launch-recovery (`millioApp.presentRestoreFlowIfNeeded` + `RestoreView`).
/// Сроки жизни у них разные и это часть контракта:
/// - счётчик попыток — **глобальный** (семантика не менялась с R1/R7, см. план recovery-rework);
/// - отказ — **per-scope**: отказ одного аккаунта не наследуется другим (S11).
///
/// В памяти процесса состоянием recovery владеет `LaunchRecoveryGate`; здесь — только то,
/// что обязано пережить перезапуск.
struct LaunchRecoveryStateStore {
    static let maxAutoRestoreAttempts = 2
    static let attemptsStorageKey = "autoRestoreAttemptCount"
    /// Префикс per-scope ключа отказа. Полный ключ = префикс + `DataScope.storeConfigurationName`.
    static let declineStorageKeyPrefix = "launchRecoveryDeclined."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Попытки авто-restore (глобально)

    var autoRestoreAttempts: Int {
        defaults.integer(forKey: Self.attemptsStorageKey)
    }

    var hasReachedAutoRestoreLimit: Bool {
        autoRestoreAttempts >= Self.maxAutoRestoreAttempts
    }

    func registerAutoRestoreAttempt() {
        defaults.set(autoRestoreAttempts + 1, forKey: Self.attemptsStorageKey)
    }

    /// Вызывается только на подтверждённом успехе restore — иначе лимит перестаёт защищать
    /// от бесконечного цикла «падение авто-restore → перезапуск».
    func resetAutoRestoreAttempts() {
        defaults.set(0, forKey: Self.attemptsStorageKey)
    }

    // MARK: - Отказ пользователя (per-scope, S11)

    static func declineStorageKey(scopeKey: String) -> String {
        declineStorageKeyPrefix + scopeKey
    }

    /// Пользователь уже выбрал «продолжить без данных» для этого scope: автоматически
    /// восстановление больше не предлагаем. Ручной путь (Профиль → Бэкап) флагом не гасится.
    func hasDeclinedRecovery(scopeKey: String) -> Bool {
        defaults.bool(forKey: Self.declineStorageKey(scopeKey: scopeKey))
    }

    func recordRecoveryDecline(scopeKey: String) {
        defaults.set(true, forKey: Self.declineStorageKey(scopeKey: scopeKey))
    }

    /// Сбрасывается, когда данные в scope появились (успешный restore или ручной ввод):
    /// прошлый отказ относился к пустому стору и больше ничего не значит.
    func clearRecoveryDecline(scopeKey: String) {
        defaults.removeObject(forKey: Self.declineStorageKey(scopeKey: scopeKey))
    }
}
