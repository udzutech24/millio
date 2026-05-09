import Foundation

/// Кэширует последний успешный DataScope в UserDefaults.
/// Цель: при временном сбое auth restore (сеть недоступна, токен истёк) приложение открывает
/// пользовательский store, а не пустой гостевой.
///
/// Использование:
/// - ScopeCache.save(_:) — после каждого успешного перехода в user scope
/// - ScopeCache.lastKnownUserID() — при обнаружении auth failure (isAuthenticated == false)
/// - ScopeCache.clearUserID() — при явном logout пользователя
enum ScopeCache {
    private static let scopeTypeKey = "millio.lastScopeType"
    private static let userIDKey = "millio.lastScopeUserID"

    static func save(_ scope: DataScope) {
        switch scope {
        case .guest:
            UserDefaults.standard.set("guest", forKey: scopeTypeKey)
            UserDefaults.standard.removeObject(forKey: userIDKey)
        case .user(let id):
            UserDefaults.standard.set("user", forKey: scopeTypeKey)
            UserDefaults.standard.set(id, forKey: userIDKey)
        }
    }

    /// Возвращает user ID из кэша, если последний scope был пользовательским.
    /// Возвращает nil если последний scope был гостевым или кэша нет.
    static func lastKnownUserID() -> String? {
        guard UserDefaults.standard.string(forKey: scopeTypeKey) == "user" else { return nil }
        return UserDefaults.standard.string(forKey: userIDKey)
    }

    /// Вызывать при явном logout — чтобы auth failure не перехватил следующий switch к guest.
    static func clearUserID() {
        UserDefaults.standard.set("guest", forKey: scopeTypeKey)
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }
}
