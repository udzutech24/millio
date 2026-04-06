//
//  DashboardLayoutStore.swift
//  millio
//
//  Created by Codex on 03.04.2026.
//

import Foundation

final class DashboardLayoutStore {
    private let defaults: UserDefaults
    private let storageKey = "dashboardWidgetConfigs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [DashboardWidgetConfig] {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([DashboardWidgetConfig].self, from: data)
        else {
            return Self.defaultConfigurations
        }
        return Self.normalize(decoded)
    }

    func save(_ configs: [DashboardWidgetConfig]) {
        let normalized = Self.normalize(configs)
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static let defaultConfigurations: [DashboardWidgetConfig] = [
        DashboardWidgetConfig(kind: .converter, isVisible: true, order: 0),
        DashboardWidgetConfig(kind: .quickActions, isVisible: true, order: 1),
        DashboardWidgetConfig(kind: .finances, isVisible: true, order: 2),
        DashboardWidgetConfig(kind: .services, isVisible: true, order: 3),
        DashboardWidgetConfig(kind: .cashflow, isVisible: true, order: 4)
    ]

    static func normalize(_ configs: [DashboardWidgetConfig]) -> [DashboardWidgetConfig] {
        var orderedUniqueConfigs: [DashboardWidgetConfig] = []
        var seenKinds = Set<DashboardWidgetKind>()

        for config in configs where seenKinds.insert(config.kind).inserted {
            orderedUniqueConfigs.append(config)
        }

        for defaultConfig in defaultConfigurations where !seenKinds.contains(defaultConfig.kind) {
            orderedUniqueConfigs.append(defaultConfig)
        }

        return orderedUniqueConfigs
            .enumerated()
            .map { index, config in
                DashboardWidgetConfig(
                    kind: config.kind,
                    isVisible: config.isVisible,
                    order: index
                )
            }
    }
}
