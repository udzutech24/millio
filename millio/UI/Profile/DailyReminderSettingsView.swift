//
//  DailyReminderSettingsView.swift
//  millio
//
//  Created by Codex on 11.03.2026.
//

import SwiftUI

struct DailyReminderSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var draftSettings = SettingsManager.shared.dailyReminderSettings
    @State private var didSave = false

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    FinancesSectionHeader(title: titleText)
                    FinancesGlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: $draftSettings.isEnabled) {
                                rowLabel(
                                    iconSystemName: "bell.fill",
                                    title: localized("profile.daily_reminders.enabled", fallback: "Enable reminders")
                                )
                            }
                            .tint(AppColors.toggleOnGreen)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)

                            if draftSettings.isEnabled {
                                FinancesRowDivider()

                                VStack(spacing: 14) {
                                    labeledControl(
                                        title: localized("profile.daily_reminders.kind", fallback: "What to remind")
                                    ) {
                                        VStack(spacing: 10) {
                                            reminderKindToggleRow(for: .expense)
                                            reminderKindToggleRow(for: .income)
                                            reminderKindToggleRow(for: .custom)
                                        }
                                    }

                                    labeledControl(
                                        title: localized("profile.daily_reminders.schedule", fallback: "Schedule")
                                    ) {
                                        Picker("", selection: $draftSettings.cadence) {
                                            Text(localized("profile.daily_reminders.schedule.daily", fallback: "Every day")).tag(DailyReminderCadence.daily)
                                            Text(localized("profile.daily_reminders.schedule.monthly", fallback: "Day of month")).tag(DailyReminderCadence.monthly)
                                            Text(localized("profile.daily_reminders.schedule.once", fallback: "Specific date")).tag(DailyReminderCadence.once)
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    if draftSettings.cadence == .monthly {
                                        labeledControl(
                                            title: localized("profile.daily_reminders.day_of_month", fallback: "Day of month")
                                        ) {
                                            Stepper(value: $draftSettings.dayOfMonth, in: 1...31) {
                                                Text("\(draftSettings.dayOfMonth)")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(AppColors.textPrimary)
                                            }
                                        }
                                    }

                                    if draftSettings.cadence == .once {
                                        labeledControl(
                                            title: localized("profile.daily_reminders.date", fallback: "Date")
                                        ) {
                                            DatePicker(
                                                "",
                                                selection: $draftSettings.selectedDate,
                                                in: Date()...,
                                                displayedComponents: .date
                                            )
                                            .labelsHidden()
                                            .colorScheme(.dark)
                                        }
                                    }

                                    labeledControl(
                                        title: localized("profile.daily_reminders.time", fallback: "Time")
                                    ) {
                                        DatePicker(
                                            "",
                                            selection: reminderTimeBinding,
                                            displayedComponents: .hourAndMinute
                                        )
                                        .labelsHidden()
                                        .colorScheme(.dark)
                                    }

                                    if draftSettings.isKindEnabled(.custom) {
                                        labeledControl(
                                            title: localized("profile.daily_reminders.custom_text", fallback: "Reminder text")
                                        ) {
                                            TextField(
                                                localized("profile.daily_reminders.custom_placeholder", fallback: "For example: add expenses"),
                                                text: $draftSettings.customText,
                                                axis: .vertical
                                            )
                                            .font(.system(size: 16, weight: .regular))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .lineLimit(2...4)
                                            .textFieldStyle(.plain)
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        }
                    }

                    Text(helperText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if draftSettings.isActive {
                        FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(localized("profile.daily_reminders.summary.title", fallback: "Current setup"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppColors.textSecondary)
                                    Text(configuredSummaryText)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                }

                                FinancesRowDivider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(localized("profile.daily_reminders.preview.title", fallback: "Notification preview"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppColors.textSecondary)
                                    Text(previewMessageText)
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localized("profile.done", fallback: "Done")) {
                    saveAndDismiss()
                }
            }
        }
        .onDisappear {
            saveIfNeeded()
        }
    }

    private var helperText: String {
        switch draftSettings.cadence {
        case .daily:
            return localized("profile.daily_reminders.helper.daily", fallback: "A reminder will fire every day at the selected time")
        case .monthly:
            return localized("profile.daily_reminders.helper.monthly", fallback: "A reminder will repeat every month on the selected day")
        case .once:
            return localized("profile.daily_reminders.helper.once", fallback: "A one-time reminder will fire on the selected date and time")
        }
    }

    private var configuredSummaryText: String {
        guard draftSettings.isActive else {
            return localized("profile.daily_reminders.summary.off", fallback: "Reminders are disabled.")
        }

        let kindText = draftSettings.sortedEnabledKinds.map(kindTitle).joined(separator: ", ")

        let timeText = String(format: "%02d:%02d", locale: locale, draftSettings.hour, draftSettings.minute)

        switch draftSettings.cadence {
        case .daily:
            return localized(
                "profile.daily_reminders.summary.daily",
                fallback: "You will get a {kind} reminder every day at {time}"
            )
            .replacingOccurrences(of: "{kind}", with: kindText.lowercased())
            .replacingOccurrences(of: "{time}", with: timeText)
        case .monthly:
            return localized(
                "profile.daily_reminders.summary.monthly",
                fallback: "You will get a {kind} reminder every month on day {day} at {time}"
            )
            .replacingOccurrences(of: "{kind}", with: kindText.lowercased())
            .replacingOccurrences(of: "{day}", with: String(draftSettings.dayOfMonth))
            .replacingOccurrences(of: "{time}", with: timeText)
        case .once:
            let dateText = draftSettings.selectedDate.formatted(date: .abbreviated, time: .omitted)
            return localized(
                "profile.daily_reminders.summary.once",
                fallback: "You will get a one-time {kind} reminder on {date} at {time}"
            )
            .replacingOccurrences(of: "{kind}", with: kindText.lowercased())
            .replacingOccurrences(of: "{date}", with: dateText)
            .replacingOccurrences(of: "{time}", with: timeText)
        }
    }

    private var previewMessageText: String {
        draftSettings.sortedEnabledKinds.map {
            draftSettings.notificationBody(
                for: $0,
                language: appState.selectedLanguage,
                calendar: Calendar.current,
                now: Date()
            )
        }.joined(separator: "\n")
    }

    private var titleText: String {
        localized("profile.reminders", fallback: "Reminders")
    }

    private var locale: Locale {
        appState.selectedLanguage.locale ?? Locale.current
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: draftSettings.selectedDate)
                components.hour = draftSettings.hour
                components.minute = draftSettings.minute
                return calendar.date(from: components) ?? draftSettings.selectedDate
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                draftSettings.hour = components.hour ?? DailyReminderSettings.defaultHour
                draftSettings.minute = components.minute ?? DailyReminderSettings.defaultMinute
            }
        )
    }

    private func saveAndDismiss() {
        saveIfNeeded()
        dismiss()
    }

    private func saveIfNeeded() {
        guard !didSave else { return }
        let normalized = draftSettings.normalized()
        let didPersist = SettingsManager.shared.updateDailyReminderSettingsIfNeeded(normalized)
        if didPersist {
            // Avoid triggering parent view updates during pop if nothing changed.
            appState.isDailyReminderEnabled = normalized.isActive
            Task {
                await NotificationManager.shared.scheduleDailyReminder(using: normalized)
            }
        }

        didSave = true
    }

    private func rowLabel(iconSystemName: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 22, alignment: .leading)
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func labeledControl<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reminderKindToggleRow(for kind: DailyReminderKind) -> some View {
        Toggle(
            isOn: Binding(
                get: { draftSettings.isKindEnabled(kind) },
                set: { draftSettings.setKind(kind, enabled: $0) }
            )
        ) {
            Text(kindTitle(kind))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
        }
        .tint(AppColors.toggleOnGreen)
    }

    private func kindTitle(_ kind: DailyReminderKind) -> String {
        switch kind {
        case .expense:
            return localized("profile.daily_reminders.kind.expense", fallback: "Expense")
        case .income:
            return localized("profile.daily_reminders.kind.income", fallback: "Income")
        case .custom:
            return localized("profile.daily_reminders.kind.custom", fallback: "Custom")
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: russianFallbacks[key] ?? fallback)
    }

    private var russianFallbacks: [String: String] {
        guard locale.identifier.lowercased().hasPrefix("ru") else { return [:] }
        return [
            "profile.reminders": "Напоминания",
            "profile.daily_reminders.enabled": "Включить напоминания",
            "profile.daily_reminders.kind": "Что напомнить",
            "profile.daily_reminders.kind.expense": "Расходы",
            "profile.daily_reminders.kind.income": "Доходы",
            "profile.daily_reminders.kind.custom": "Свое",
            "profile.daily_reminders.schedule": "Периодичность",
            "profile.daily_reminders.schedule.daily": "Каждый день",
            "profile.daily_reminders.schedule.monthly": "День месяца",
            "profile.daily_reminders.schedule.once": "Дата",
            "profile.daily_reminders.day_of_month": "День месяца",
            "profile.daily_reminders.date": "Дата",
            "profile.daily_reminders.time": "Время",
            "profile.daily_reminders.custom_text": "Текст напоминания",
            "profile.daily_reminders.custom_placeholder": "Например: внести расходы",
            "profile.daily_reminders.helper.daily": "Напоминание будет приходить каждый день в выбранное время",
            "profile.daily_reminders.helper.monthly": "Напоминание будет повторяться каждый месяц в выбранный день",
            "profile.daily_reminders.helper.once": "Разовое напоминание сработает в выбранные дату и время",
            "profile.daily_reminders.summary.title": "Сейчас настроено",
            "profile.daily_reminders.preview.title": "Пример уведомления",
            "profile.daily_reminders.summary.off": "Напоминания выключены.",
            "profile.daily_reminders.summary.daily": "Будет приходить напоминание про {kind}, каждый день в {time}",
            "profile.daily_reminders.summary.monthly": "Будет приходить напоминание про {kind}, каждый месяц {day}-го числа в {time}",
            "profile.daily_reminders.summary.once": "Придет разовое напоминание про {kind}: {date} в {time}"
        ]
    }
}

#Preview {
    NavigationStack {
        DailyReminderSettingsView()
            .environment(AppState())
    }
}
