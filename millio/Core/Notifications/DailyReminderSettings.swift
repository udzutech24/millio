//
//  DailyReminderSettings.swift
//  millio
//
//  Created by Codex on 11.03.2026.
//

import Foundation

enum DailyReminderKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income
    case custom

    var id: String { rawValue }
}

enum DailyReminderCadence: String, Codable, CaseIterable, Identifiable {
    case daily
    case monthly
    case once

    var id: String { rawValue }
}

/// Хранит пользовательский сценарий локального напоминания в UserDefaults.
/// Пока поддерживаем один активный сценарий, чтобы не усложнять UX и планировщик.
struct DailyReminderSettings: Codable, Equatable {
    static let defaultHour = 20
    static let defaultMinute = 0
    static let defaultDayOfMonth = 1
    static let notificationIdentifierPrefix = "daily_reminder"

    var isEnabled: Bool
    var enabledKinds: [DailyReminderKind]
    var cadence: DailyReminderCadence
    var hour: Int
    var minute: Int
    var dayOfMonth: Int
    var selectedDate: Date
    var customText: String

    static var `default`: DailyReminderSettings {
        DailyReminderSettings(
            isEnabled: false,
            enabledKinds: [.expense],
            cadence: .daily,
            hour: defaultHour,
            minute: defaultMinute,
            dayOfMonth: defaultDayOfMonth,
            selectedDate: Calendar.current.startOfDay(for: Date()),
            customText: ""
        )
    }

    var trimmedCustomText: String {
        customText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasEnabledKinds: Bool {
        !sortedEnabledKinds.isEmpty
    }

    var isActive: Bool {
        isEnabled && hasEnabledKinds
    }

    var sortedEnabledKinds: [DailyReminderKind] {
        DailyReminderKind.allCases.filter { enabledKinds.contains($0) }
    }

    func normalized(calendar: Calendar = .current, now: Date = Date()) -> DailyReminderSettings {
        var normalized = self
        normalized.hour = min(max(hour, 0), 23)
        normalized.minute = min(max(minute, 0), 59)
        normalized.dayOfMonth = min(max(dayOfMonth, 1), 31)
        normalized.enabledKinds = normalized.sortedEnabledKinds

        let startOfToday = calendar.startOfDay(for: now)
        if selectedDate < startOfToday {
            normalized.selectedDate = startOfToday
        }

        return normalized
    }

    func notificationBody(
        for kind: DailyReminderKind,
        language: Language = LanguageManager.shared.currentLanguage,
        fallbackLocale: Locale = .current,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> String {
        let locale = LocalizationSupport.resolvedLocale(for: language, fallbackLocale: fallbackLocale)

        switch kind {
        case .expense:
            let messages = [
                localizedNotificationBody("profile.daily_reminders.notification.expense.1", locale: locale, fallback: "Time to log today's expenses"),
                localizedNotificationBody("profile.daily_reminders.notification.expense.2", locale: locale, fallback: "Add today's spending while it's still fresh"),
                localizedNotificationBody("profile.daily_reminders.notification.expense.3", locale: locale, fallback: "Record your expenses and keep your balance accurate")
            ]
            return messages[messageIndex(calendar: calendar, now: now) % messages.count]
        case .income:
            let messages = [
                localizedNotificationBody("profile.daily_reminders.notification.income.1", locale: locale, fallback: "Time to log new income"),
                localizedNotificationBody("profile.daily_reminders.notification.income.2", locale: locale, fallback: "Record incoming funds to keep your balance up to date"),
                localizedNotificationBody("profile.daily_reminders.notification.income.3", locale: locale, fallback: "Add your income and refresh your financial overview")
            ]
            return messages[messageIndex(calendar: calendar, now: now) % messages.count]
        case .custom:
            if !trimmedCustomText.isEmpty {
                return trimmedCustomText
            }
            return localizedNotificationBody(
                "profile.daily_reminders.notification.custom.default",
                locale: locale,
                fallback: "Open millio and update your data"
            )
        }
    }

    private func messageIndex(calendar: Calendar, now: Date) -> Int {
        calendar.component(.day, from: now)
    }

    private func localizedNotificationBody(_ key: String, locale: Locale, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }

    func isKindEnabled(_ kind: DailyReminderKind) -> Bool {
        enabledKinds.contains(kind)
    }

    mutating func setKind(_ kind: DailyReminderKind, enabled: Bool) {
        if enabled {
            if !enabledKinds.contains(kind) {
                enabledKinds.append(kind)
            }
        } else {
            enabledKinds.removeAll { $0 == kind }
        }
    }

    static func notificationIdentifier(for kind: DailyReminderKind) -> String {
        "\(notificationIdentifierPrefix).\(kind.rawValue)"
    }
}
