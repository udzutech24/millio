import Foundation

/// Remembers an explicit recovery outcome per non-reversible data-scope name.
/// A missing value intentionally means "not acknowledged" so an update can
/// recover users who previously fell through to an empty dashboard while
/// CloudKit was still resolving.
enum RecoveryPromptStore {
    // v2 invalidates acknowledgements written by the former all-model count,
    // which incorrectly treated reference/cache rows as user financial data.
    private static let prefix = "recoveryPromptAcknowledged.v2."

    static func isAcknowledged(scopeIdentifier: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: prefix + scopeIdentifier)
    }

    static func acknowledge(scopeIdentifier: String, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: prefix + scopeIdentifier)
    }
}
