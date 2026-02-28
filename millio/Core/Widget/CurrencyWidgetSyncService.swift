//
//  CurrencyWidgetSyncService.swift
//  millio
//
//  Created by Codex on 24.02.2026.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
enum CurrencyWidgetSyncService {
    private static let knownRateSources = ["erapi", "frankfurter"]
    private static var lastReloadAt: Date = .distantPast
    private static let minimumReloadInterval: TimeInterval = 1

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: CurrencyWidgetShared.appGroupID)
    }

    static func bootstrapFromStandardDefaults(defaults: UserDefaults = .standard) {
        guard let sharedDefaults else { return }

        set(defaults.object(forKey: CurrencyWidgetShared.Keys.selectedCodes), forKey: CurrencyWidgetShared.Keys.selectedCodes, in: sharedDefaults)
        set(defaults.object(forKey: CurrencyWidgetShared.Keys.activeCode), forKey: CurrencyWidgetShared.Keys.activeCode, in: sharedDefaults)
        set(defaults.object(forKey: CurrencyWidgetShared.Keys.inputText), forKey: CurrencyWidgetShared.Keys.inputText, in: sharedDefaults)
        set(defaults.object(forKey: CurrencyWidgetShared.Keys.rateSource), forKey: CurrencyWidgetShared.Keys.rateSource, in: sharedDefaults)

        for source in knownRateSources {
            let ratesKey = CurrencyWidgetShared.Keys.cachedRates(for: source)
            let timestampKey = CurrencyWidgetShared.Keys.lastRatesTimestamp(for: source)
            set(defaults.object(forKey: ratesKey), forKey: ratesKey, in: sharedDefaults)
            set(defaults.object(forKey: timestampKey), forKey: timestampKey, in: sharedDefaults)
        }

        set(defaults.object(forKey: CurrencyWidgetShared.Keys.subscriptionStatus), forKey: CurrencyWidgetShared.Keys.subscriptionStatus, in: sharedDefaults)
        set(defaults.object(forKey: CurrencyWidgetShared.Keys.subscriptionExpiration), forKey: CurrencyWidgetShared.Keys.subscriptionExpiration, in: sharedDefaults)
        set(defaults.object(forKey: CurrencyWidgetShared.Keys.subscriptionIsTrialActive), forKey: CurrencyWidgetShared.Keys.subscriptionIsTrialActive, in: sharedDefaults)
        set(defaults.object(forKey: CurrencyWidgetShared.Keys.debugPremiumEnabled), forKey: CurrencyWidgetShared.Keys.debugPremiumEnabled, in: sharedDefaults)
        set(defaults.object(forKey: CurrencyWidgetShared.Keys.debugSubscriptionExpiration), forKey: CurrencyWidgetShared.Keys.debugSubscriptionExpiration, in: sharedDefaults)

        reloadWidgetTimelines(force: true)
    }

    static func setString(_ value: String, forKey key: String) {
        setAny(value, forKey: key)
    }

    static func setInt(_ value: Int, forKey key: String) {
        setAny(value, forKey: key)
    }

    static func setDouble(_ value: Double, forKey key: String) {
        setAny(value, forKey: key)
    }

    static func setBool(_ value: Bool, forKey key: String) {
        setAny(value, forKey: key)
    }

    static func setRates(_ rates: [String: Double], forSource sourceRaw: String) {
        let key = CurrencyWidgetShared.Keys.cachedRates(for: sourceRaw)
        setAny(rates, forKey: key)
    }

    static func setLastRatesTimestamp(_ timestamp: Double, forSource sourceRaw: String) {
        let key = CurrencyWidgetShared.Keys.lastRatesTimestamp(for: sourceRaw)
        setAny(timestamp, forKey: key)
    }

    static func syncSubscription(
        statusRaw: String,
        expirationDate: Date?,
        isTrialActive: Bool,
        debugPremiumEnabled: Bool,
        debugPremiumExpiration: Date?
    ) {
        guard let sharedDefaults else { return }

        set(statusRaw, forKey: CurrencyWidgetShared.Keys.subscriptionStatus, in: sharedDefaults)
        set(expirationDate, forKey: CurrencyWidgetShared.Keys.subscriptionExpiration, in: sharedDefaults)
        set(isTrialActive, forKey: CurrencyWidgetShared.Keys.subscriptionIsTrialActive, in: sharedDefaults)
        set(debugPremiumEnabled, forKey: CurrencyWidgetShared.Keys.debugPremiumEnabled, in: sharedDefaults)
        set(debugPremiumExpiration, forKey: CurrencyWidgetShared.Keys.debugSubscriptionExpiration, in: sharedDefaults)

        reloadWidgetTimelines(force: true)
    }

    private static func setAny(_ value: Any?, forKey key: String) {
        guard let sharedDefaults else { return }
        set(value, forKey: key, in: sharedDefaults)
        reloadWidgetTimelines()
    }

    private static func set(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func reloadWidgetTimelines(force: Bool = false) {
        #if canImport(WidgetKit)
        let now = Date()
        if !force, now.timeIntervalSince(lastReloadAt) < minimumReloadInterval {
            return
        }
        lastReloadAt = now
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
