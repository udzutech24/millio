//
//  DailyReminderLocalization.swift
//  millio
//
//  Created by Codex on 01.04.2026.
//

import Foundation

enum DailyReminderLocalization {
    static func title(locale: Locale) -> String {
        localized("profile.daily_reminders", locale: locale, fallback: "Daily reminders")
    }

    static func helperText(for cadence: DailyReminderCadence, locale: Locale) -> String {
        switch cadence {
        case .daily:
            return localized(
                "profile.daily_reminders.helper.daily",
                locale: locale,
                fallback: "A reminder will fire every day at the selected time"
            )
        case .monthly:
            return localized(
                "profile.daily_reminders.helper.monthly",
                locale: locale,
                fallback: "A reminder will repeat every month on the selected day"
            )
        case .once:
            return localized(
                "profile.daily_reminders.helper.once",
                locale: locale,
                fallback: "A one-time reminder will fire on the selected date and time"
            )
        }
    }

    static func kindTitle(_ kind: DailyReminderKind, locale: Locale) -> String {
        switch kind {
        case .expense:
            return localized("profile.daily_reminders.kind.expense", locale: locale, fallback: "Expenses")
        case .income:
            return localized("profile.daily_reminders.kind.income", locale: locale, fallback: "Income")
        case .custom:
            return localized("profile.daily_reminders.kind.custom", locale: locale, fallback: "Custom")
        }
    }

    static func configuredSummaryText(
        settings: DailyReminderSettings,
        locale: Locale,
        calendar: Calendar = .current
    ) -> String {
        guard settings.isActive else {
            return localized(
                "profile.daily_reminders.summary.off",
                locale: locale,
                fallback: "Reminders are disabled."
            )
        }

        let subject = summarySubject(for: settings.sortedEnabledKinds, locale: locale)
        let timeText = formattedTime(for: settings, locale: locale, calendar: calendar)

        switch settings.cadence {
        case .daily:
            return localized(
                "profile.daily_reminders.summary.daily",
                locale: locale,
                fallback: "You will get a {kind} reminder every day at {time}"
            )
            .replacingOccurrences(of: "{kind}", with: subject)
            .replacingOccurrences(of: "{time}", with: timeText)
        case .monthly:
            return localized(
                "profile.daily_reminders.summary.monthly",
                locale: locale,
                fallback: "You will get a {kind} reminder every month on day {day} at {time}"
            )
            .replacingOccurrences(of: "{kind}", with: subject)
            .replacingOccurrences(of: "{day}", with: String(settings.dayOfMonth))
            .replacingOccurrences(of: "{time}", with: timeText)
        case .once:
            let dateText = settings.selectedDate.formatted(
                Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
            )
            return localized(
                "profile.daily_reminders.summary.once",
                locale: locale,
                fallback: "You will get a one-time {kind} reminder on {date} at {time}"
            )
            .replacingOccurrences(of: "{kind}", with: subject)
            .replacingOccurrences(of: "{date}", with: dateText)
            .replacingOccurrences(of: "{time}", with: timeText)
        }
    }

    private static func summarySubject(for enabledKinds: [DailyReminderKind], locale: Locale) -> String {
        guard enabledKinds.count == 1, let kind = enabledKinds.first else {
            return localized(
                "profile.daily_reminders.summary.kind.selected",
                locale: locale,
                fallback: "selected items"
            )
        }

        switch kind {
        case .expense:
            return localized(
                "profile.daily_reminders.summary.kind.expense",
                locale: locale,
                fallback: "expenses"
            )
        case .income:
            return localized(
                "profile.daily_reminders.summary.kind.income",
                locale: locale,
                fallback: "income"
            )
        case .custom:
            return localized(
                "profile.daily_reminders.summary.kind.custom",
                locale: locale,
                fallback: "custom notes"
            )
        }
    }

    private static func formattedTime(
        for settings: DailyReminderSettings,
        locale: Locale,
        calendar: Calendar
    ) -> String {
        var components = calendar.dateComponents([.year, .month, .day], from: settings.selectedDate)
        components.hour = settings.hour
        components.minute = settings.minute
        let date = calendar.date(from: components) ?? settings.selectedDate
        return date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        )
    }

    private static func localized(_ key: String, locale: Locale, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }
}
