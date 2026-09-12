//
//  DashboardWidgetID.swift
//  millio
//

import Foundation

enum DashboardWidgetID: String, CaseIterable, Codable, Identifiable {
    case firstSteps = "firstSteps"
    case totalBalance = "totalBalance"
    case quickActions = "quickActions"
    case cashflowSummary = "cashflowSummary"
    case currencyRates = "currencyRates"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstSteps: return L("first_steps.title")
        case .totalBalance: return L("Общий баланс")
        case .quickActions: return L("Быстрые действия")
        case .cashflowSummary: return L("Кэшфлоу за период")
        case .currencyRates: return L("dashboard.currency_rates.title")
        }
    }

    var iconName: String {
        switch self {
        case .firstSteps: return "checklist"
        case .totalBalance: return "chart.line.uptrend.xyaxis"
        case .quickActions: return "bolt.fill"
        case .cashflowSummary: return "arrow.up.arrow.down.circle.fill"
        case .currencyRates: return "arrow.2.squarepath"
        }
    }
}

enum DashboardWidgetStorage {
    private static let key = "dashboard.active_widgets.v1"
    private static let firstStepsInjectedKey = "dashboard.firstSteps.injected"
    static let defaultWidgets: [DashboardWidgetID] = [.firstSteps, .totalBalance, .quickActions, .cashflowSummary, .currencyRates]

    static func load() -> [DashboardWidgetID] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DashboardWidgetID].self, from: data)
        else { return defaultWidgets }
        return injectingFirstStepsOnce(into: decoded)
    }

    /// В сохранённом у пользователя массиве нового виджета нет, и сам он там не появится.
    /// Поэтому — ровно одна инъекция за всё время жизни установки: флаг ставится сразу,
    /// поэтому удалённый виджет обратно не возвращается.
    private static func injectingFirstStepsOnce(into widgets: [DashboardWidgetID]) -> [DashboardWidgetID] {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: firstStepsInjectedKey) else { return widgets }
        defaults.set(true, forKey: firstStepsInjectedKey)

        guard !widgets.contains(.firstSteps) else { return widgets }
        let injected = [.firstSteps] + widgets
        save(injected)
        return injected
    }

    static func save(_ widgets: [DashboardWidgetID]) {
        guard let data = try? JSONEncoder().encode(widgets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
