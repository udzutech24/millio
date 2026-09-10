//
//  DashboardWidgetID.swift
//  millio
//

import Foundation

enum DashboardWidgetID: String, CaseIterable, Codable, Identifiable {
    case totalBalance = "totalBalance"
    case aiSummary = "aiSummary"
    case quickActions = "quickActions"
    case cashflowSummary = "cashflowSummary"
    case currencyRates = "currencyRates"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .totalBalance: return L("Общий баланс")
        case .aiSummary: return L("dashboard.ai_summary.title")
        case .quickActions: return L("Быстрые действия")
        case .cashflowSummary: return L("Кэшфлоу за период")
        case .currencyRates: return L("dashboard.currency_rates.title")
        }
    }

    var iconName: String {
        switch self {
        case .totalBalance: return "chart.line.uptrend.xyaxis"
        case .aiSummary: return "sparkles"
        case .quickActions: return "bolt.fill"
        case .cashflowSummary: return "arrow.up.arrow.down.circle.fill"
        case .currencyRates: return "arrow.2.squarepath"
        }
    }
}

enum DashboardWidgetStorage {
    private static let key = "dashboard.active_widgets.v1"
    private static let offeredKey = "dashboard.active_widgets.offered_ids.v1"

    static let defaultWidgets: [DashboardWidgetID] = [
        .totalBalance, .aiSummary, .quickActions, .cashflowSummary, .currencyRates
    ]

    /// Виджеты, появившиеся ПОСЛЕ того, как у пользователя уже был сохранён набор.
    /// `load()` возвращает сохранённый массив, поэтому без явной дозаписи новый виджет
    /// не появился бы ни у кого, кто хоть раз открывал настройки дашборда.
    static let widgetsIntroducedAfterInitialRelease: [DashboardWidgetID] = [.aiSummary]

    static func load() -> [DashboardWidgetID] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DashboardWidgetID].self, from: data)
        else {
            // Дефолтный набор уже содержит новые виджеты — помечаем их предложенными, иначе
            // после первого же сохранения они дозаписались бы повторно.
            markOffered(widgetsIntroducedAfterInitialRelease.map(\.rawValue))
            return defaultWidgets
        }

        let result = applyingIntroducedWidgets(
            to: decoded,
            introduced: widgetsIntroducedAfterInitialRelease,
            alreadyOffered: offeredIDs()
        )
        if result.widgets != decoded { save(result.widgets) }
        markOffered(result.offered)
        return result.widgets
    }

    static func save(_ widgets: [DashboardWidgetID]) {
        guard let data = try? JSONEncoder().encode(widgets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Дозапись новых виджетов

    /// Чистая логика миграции набора виджетов.
    /// Каждый новый ID дозаписывается РОВНО ОДИН РАЗ: если пользователь потом убрал виджет руками,
    /// он не возвращается при следующем запуске.
    static func applyingIntroducedWidgets(
        to saved: [DashboardWidgetID],
        introduced: [DashboardWidgetID],
        alreadyOffered: Set<String>
    ) -> (widgets: [DashboardWidgetID], offered: Set<String>) {
        var widgets = saved
        var offered = alreadyOffered
        for widget in introduced {
            offered.insert(widget.rawValue)
            guard !alreadyOffered.contains(widget.rawValue), !widgets.contains(widget) else { continue }
            widgets.insert(widget, at: insertionIndex(for: widget, in: widgets))
        }
        return (widgets, offered)
    }

    /// Место новичка в чужом порядке: сразу ЗА последним виджетом, который в дефолтном наборе
    /// стоит раньше него. Так карточка итогов встаёт под «Общий баланс» даже если пользователь
    /// переставил остальные виджеты. Искать «первого, кто стоит позже» нельзя — переставленный
    /// в начало виджет с большим порядком выкинул бы новичка на нулевую позицию.
    static func insertionIndex(for widget: DashboardWidgetID, in widgets: [DashboardWidgetID]) -> Int {
        guard let order = defaultWidgets.firstIndex(of: widget) else { return widgets.count }
        var index = 0
        for (position, existing) in widgets.enumerated() {
            guard let existingOrder = defaultWidgets.firstIndex(of: existing) else { continue }
            if existingOrder < order { index = position + 1 }
        }
        return index
    }

    private static func offeredIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: offeredKey) ?? [])
    }

    private static func markOffered<S: Sequence>(_ ids: S) where S.Element == String {
        let current = offeredIDs()
        let updated = current.union(ids)
        let isRecorded = UserDefaults.standard.stringArray(forKey: offeredKey) != nil
        guard updated != current || !isRecorded else { return }
        UserDefaults.standard.set(Array(updated).sorted(), forKey: offeredKey)
    }
}
