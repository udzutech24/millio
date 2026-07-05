import Foundation

/// Гейт повторов reconciliation (Track B, спека §3). Done-маркер по `storeConfigurationName` —
/// merge выполняется один раз на пользователя; force-signout/relogin не переигрывает выполненный merge.
enum ScopeMergeMarker {
    private static func doneKey(_ key: String) -> String { "reconciliation.done.\(key)" }
    private static func reportKey(_ key: String) -> String { "reconciliation.report.\(key)" }
    private static func confirmKey(_ key: String) -> String { "reconciliation.needsConfirmation.\(key)" }

    static func isDone(userScopeKey: String) -> Bool {
        UserDefaults.standard.bool(forKey: doneKey(userScopeKey))
    }

    /// Фиксирует done ТОЛЬКО после успешного save (митигация B1b №5). Хранит counts в маркере.
    static func markDone(userScopeKey: String, report: ScopeMergeReport) {
        storeReport(userScopeKey: userScopeKey, report: report)
        UserDefaults.standard.set(true, forKey: doneKey(userScopeKey))
    }

    /// Сохраняет counts БЕЗ выставления done — для партиально-читаемого стора (митигация B1b №6):
    /// merge применён, но при чистом открытии стора его нужно повторить.
    static func storeReport(userScopeKey: String, report: ScopeMergeReport) {
        if let data = try? JSONEncoder().encode(report) {
            UserDefaults.standard.set(data, forKey: reportKey(userScopeKey))
        }
    }

    static func storedReport(userScopeKey: String) -> ScopeMergeReport? {
        guard let data = UserDefaults.standard.data(forKey: reportKey(userScopeKey)) else { return nil }
        return try? JSONDecoder().decode(ScopeMergeReport.self, from: data)
    }

    /// Чужой guest на шаренном устройстве (митигация B1b №1) — отложено до подтверждения владельца.
    static func markNeedsConfirmation(userScopeKey: String) {
        UserDefaults.standard.set(true, forKey: confirmKey(userScopeKey))
    }

    static func needsConfirmation(userScopeKey: String) -> Bool {
        UserDefaults.standard.bool(forKey: confirmKey(userScopeKey))
    }
}

/// Трекер сторов, открытых через no-plan fallback (V4, «partially readable», митигация B1b №6).
/// Заполняется в `millioApp.makeModelContainer`; reconciliation по нему решает НЕ ставить done.
final class ScopeStoreOpenTracker: @unchecked Sendable {
    static let shared = ScopeStoreOpenTracker()
    private let lock = NSLock()
    private var fallbackScopes: Set<String> = []

    func markFallback(_ scopeKey: String) {
        lock.lock(); fallbackScopes.insert(scopeKey); lock.unlock()
    }

    func usedFallback(_ scopeKey: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return fallbackScopes.contains(scopeKey)
    }
}

/// In-memory флаг «merge в процессе» (митигация B1b №7: блокировка бэкапа во время merge).
/// НЕ персистентный: краш посреди merge не должен навсегда заблокировать бэкап.
final class ScopeMergeLock: @unchecked Sendable {
    static let shared = ScopeMergeLock()
    private let lock = NSLock()
    private var inProgress = false

    var isMergeInProgress: Bool {
        lock.lock(); defer { lock.unlock() }
        return inProgress
    }

    func begin() { lock.lock(); inProgress = true; lock.unlock() }
    func end() { lock.lock(); inProgress = false; lock.unlock() }
}
