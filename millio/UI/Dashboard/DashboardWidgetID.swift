//
//  DashboardWidgetID.swift
//  millio
//

import Foundation

enum DashboardWidgetID: String, CaseIterable, Codable, Identifiable {
    case totalBalance = "totalBalance"
    case quickActions = "quickActions"
    case cashflowSummary = "cashflowSummary"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .totalBalance: return L("Общий баланс")
        case .quickActions: return L("Быстрые действия")
        case .cashflowSummary: return L("Кэшфлоу за период")
        }
    }

    var iconName: String {
        switch self {
        case .totalBalance: return "chart.line.uptrend.xyaxis"
        case .quickActions: return "bolt.fill"
        case .cashflowSummary: return "arrow.up.arrow.down.circle.fill"
        }
    }
}

enum DashboardWidgetStorage {
    private static let key = "dashboard.active_widgets.v1"
    static let defaultWidgets: [DashboardWidgetID] = [.totalBalance, .quickActions, .cashflowSummary]

    static func load() -> [DashboardWidgetID] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DashboardWidgetID].self, from: data)
        else { return defaultWidgets }
        return decoded
    }

    static func save(_ widgets: [DashboardWidgetID]) {
        guard let data = try? JSONEncoder().encode(widgets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
