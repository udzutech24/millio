import Foundation
import ObjectiveC.runtime

enum BundleLanguageOverride {
    private static var installedBundleIDs = Set<ObjectIdentifier>()
    private static var associatedBundleKey: UInt8 = 0
    private static let overrideStateLock = NSLock()
    private static var overrideSuppressionDepth = 0

    static func apply(language: Language) {
        let bundles = Set([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks)
        for bundle in bundles {
            installOverrideIfNeeded(on: bundle)
            let localizedBundle = language.locale.flatMap {
                AppLocalization.localizedBundle(for: $0, bundle: bundle)
            }
            objc_setAssociatedObject(
                bundle,
                &associatedBundleKey,
                localizedBundle,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
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
