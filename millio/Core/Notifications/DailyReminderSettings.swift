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
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> String {
        let isRussian = Self.isRussian(language: language)

        switch kind {
        case .expense:
            let messages = isRussian
                ? [
                    "Пора внести расходы за сегодня.",
                    "Добавь сегодняшние траты, пока все помнишь.",
                    "Запиши расходы и держи баланс точным."
                ]
                : [
                    "Time to log today's expenses.",
                    "Add today's spending while it's still fresh.",
                    "Record your expenses and keep your balance accurate."
                ]
            return messages[messageIndex(calendar: calendar, now: now) % messages.count]
        case .income:
            let messages = isRussian
                ? [
                    "Пора внести новые доходы.",
                    "Запиши поступления, чтобы баланс был актуальным.",
                    "Добавь доходы и обнови картину по финансам."
                ]
                : [
                    "Time to log new income.",
                    "Record incoming funds to keep your balance up to date.",
                    "Add your income and refresh your financial overview."
                ]
            return messages[messageIndex(calendar: calendar, now: now) % messages.count]
        case .custom:
            if !trimmedCustomText.isEmpty {
                return trimmedCustomText
            }
            return isRussian ? "Открой millio и обнови данные." : "Open millio and update your data."
        }
    }

    private func messageIndex(calendar: Calendar, now: Date) -> Int {
        calendar.component(.day, from: now)
    }

    private static func isRussian(language: Language) -> Bool {
        switch language {
        case .russian:
            return true
        case .english:
            return false
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? Locale.current.identifier.lowercased()
            return preferred.hasPrefix("ru")
        }
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
