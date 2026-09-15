import Foundation
import ObjectiveC.runtime
import OSLog

enum BundleLanguageOverride {
    private static var installedBundleIDs = Set<ObjectIdentifier>()
    private static var associatedBundleKey: UInt8 = 0
    private static let overrideStateLock = NSLock()
    private static var overrideSuppressionDepth = 0

    static func apply(language: Language) {
        let diagLogger = Logger(subsystem: "millio", category: "BundleOverride")
        diagLogger.debug("[BundleOverride] apply called for language: \(language.rawValue)")
        if let loc = language.locale {
            diagLogger.debug("[BundleOverride] locale identifier: \(loc.identifier)")
        } else {
            diagLogger.debug("[BundleOverride] locale is nil (system) — clearing bundle override")
        }

        // Системные фреймворки (AuthenticationServices, UIKit и т.п.) живут вне нашего
        // app bundle и обязаны показывать локализацию системы, а не нашего языка —
        // иначе кнопка Sign in with Apple рисует сырой ключ вместо системного текста
        // (система ищет строку в нашем override-бандле, где её просто нет).
        let bundles = Set([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks)
            .filter(isOwnedBundle)
        diagLogger.debug("[BundleOverride] total bundles to process: \(bundles.count)")

        for bundle in bundles {
            installOverrideIfNeeded(on: bundle)
            let localizedBundle = language.locale.flatMap {
                AppLocalization.localizedBundle(for: $0, bundle: bundle)
            }

            if bundle === Bundle.main {
                if let lb = localizedBundle {
                    diagLogger.debug("[BundleOverride] Bundle.main → localizedBundle found: \(lb.bundlePath)")
                } else {
                    diagLogger.error("[BundleOverride] ❌ localizedBundle is NIL for Bundle.main! locale=\(language.locale?.identifier ?? "nil")")
                }
            }

            objc_setAssociatedObject(
                bundle,
                &associatedBundleKey,
                localizedBundle,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
        diagLogger.debug("[BundleOverride] apply complete for language: \(language.rawValue)")
    }

    /// Бандл принадлежит нам (лежит внутри app bundle: основной таргет,
    /// наши extensions, наши SPM-ресурсные бандлы), а не системный фреймворк.
    private static func isOwnedBundle(_ bundle: Bundle) -> Bool {
        if bundle === Bundle.main { return true }
        let path = bundle.bundlePath
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") { return false }
        // Симулятор хранит системные рантайм-фреймворки под .../RuntimeRoot/System/…
        if path.contains("/RuntimeRoot/System/") || path.contains(".sdk/System/") { return false }
        return path.hasPrefix(Bundle.main.bundlePath)
    }

    private static func installOverrideIfNeeded(on bundle: Bundle) {
        let bundleID = ObjectIdentifier(bundle)
        guard !installedBundleIDs.contains(bundleID) else { return }
        installedBundleIDs.insert(bundleID)
        object_setClass(bundle, RuntimeLocalizedBundle.self)
    }

    fileprivate static func overriddenBundle(for bundle: Bundle) -> Bundle? {
        objc_getAssociatedObject(bundle, &associatedBundleKey) as? Bundle
    }

    static func rawLocalizedString(
        from bundle: Bundle,
        key: String,
        value: String? = nil,
        table tableName: String? = nil
    ) -> String {
        if let runtimeBundle = bundle as? RuntimeLocalizedBundle {
            return runtimeBundle.baseLocalizedString(forKey: key, value: value, table: tableName)
        }

        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }

    static func performWithoutOverride<T>(_ body: () -> T) -> T {
        overrideStateLock.lock()
        overrideSuppressionDepth += 1
        overrideStateLock.unlock()

        defer {
            overrideStateLock.lock()
            overrideSuppressionDepth -= 1
            overrideStateLock.unlock()
        }

        return body()
    }

    fileprivate static var isOverrideSuppressed: Bool {
        overrideStateLock.lock()
        defer { overrideStateLock.unlock() }
        return overrideSuppressionDepth > 0
    }
}

private final class RuntimeLocalizedBundle: Bundle, @unchecked Sendable {
    fileprivate func baseLocalizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        super.localizedString(forKey: key, value: value, table: tableName)
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if BundleLanguageOverride.isOverrideSuppressed {
            return baseLocalizedString(forKey: key, value: value, table: tableName)
        }
        if let overriddenBundle = BundleLanguageOverride.overriddenBundle(for: self),
           overriddenBundle !== self {
            return overriddenBundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return baseLocalizedString(forKey: key, value: value, table: tableName)
    }
}
