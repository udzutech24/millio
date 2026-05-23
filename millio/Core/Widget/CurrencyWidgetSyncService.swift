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
    // Автоматически включает новые источники (cbr и т.д.) при добавлении кейсов в RateSource
    private static let knownRateSources = RateSource.allCases.map(\.rawValue)
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
        // Виджет читает глобальный preferred_rate_source, а не локальный conv_rate_source конвертера
        set(defaults.object(forKey: "preferred_rate_source"), forKey: CurrencyWidgetShared.Keys.rateSource, in: sharedDefaults)
        set(defaults.object(forKey: CurrencyWidgetShared.Keys.primaryCurrencyCode), forKey: CurrencyWidgetShared.Keys.primaryCurrencyCode, in: sharedDefaults)

        for source in knownRateSources {
            let ratesKey = CurrencyWidgetShared.Keys.cachedRates(for: source)
            let timestampKey = CurrencyWidgetShared.Keys.lastRatesTimestamp(for: source)
            set(defaults.object(forKey: ratesKey), forKey: ratesKey, in: sharedDefaults)
            set(defaults.object(forKey: timestampKey), forKey: timestampKey, in: sharedDefaults)
        }

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
