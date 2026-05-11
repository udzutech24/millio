//
//  NotificationManager.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import UserNotifications
import OSLog

protocol UserNotificationCenterProtocol {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCenterProtocol {}

/// Протокол для управления уведомлениями
@MainActor
protocol NotificationManagerProtocol {
    func requestAuthorization() async -> Bool
    func scheduleDailyReminder(enabled: Bool) async
    func scheduleDailyReminder(using settings: DailyReminderSettings) async
    func cancelDailyReminder()
    func scheduleCashflowScheduledReminders(for transactions: [CashflowTransaction]) async
    func cancelCashflowScheduledReminders()
}

/// Менеджер локальных уведомлений
@MainActor
final class NotificationManager: NotificationManagerProtocol {
    static let shared = NotificationManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "NotificationManager")
    private let notificationCenter: any UserNotificationCenterProtocol
    private let now: () -> Date
    private let calendar: Calendar
    private let languageProvider: () -> Language
    private let defaults: UserDefaults
    private let scheduledReminderIDsKey = "cashflow_scheduled_reminder_ids"
    private static let scheduledReminderIdentifierPrefix = "cashflow_scheduled_reminder"
    
    init(
        notificationCenter: any UserNotificationCenterProtocol = UNUserNotificationCenter.current(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        languageProvider: @escaping () -> Language = { LanguageManager.shared.currentLanguage },
        defaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenter
        self.now = now
        self.calendar = calendar
        self.languageProvider = languageProvider
        self.defaults = defaults
    }
    
    // MARK: - Public Methods
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization granted: \(granted)")
            return granted
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }
    
    func scheduleDailyReminder(enabled: Bool) async {
        var settings = SettingsManager.shared.dailyReminderSettings
        settings.isEnabled = enabled
        await scheduleDailyReminder(using: settings)
    }

    func scheduleDailyReminder(using settings: DailyReminderSettings) async {
        let normalized = settings.normalized(calendar: calendar, now: now())
        guard normalized.isActive else {
            cancelDailyReminder()
            return
        }

        let authorized = await requestAuthorization()
        guard authorized else {
            logger.warning("Notification authorization not granted")
            return
        }

        cancelDailyReminder()

        guard let trigger = makeTrigger(for: normalized) else {
            logger.warning("Skipping reminder scheduling because trigger is invalid")
            return
        }

        for kind in normalized.sortedEnabledKinds {
            let content = UNMutableNotificationContent()
            content.title = "millio"
            content.body = normalized.notificationBody(
                for: kind,
                language: languageProvider(),
                calendar: calendar,
                now: now()
            )
            content.sound = .default
            content.badge = 1

            let request = UNNotificationRequest(
                identifier: DailyReminderSettings.notificationIdentifier(for: kind),
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
            } catch {
                logger.error("Failed to schedule daily reminder for \(kind.rawValue): \(error.localizedDescription)")
            }
        }
        logger.info("Daily reminders scheduled successfully")
    }
    
    func cancelDailyReminder() {
        let identifiers = DailyReminderKind.allCases.map(DailyReminderSettings.notificationIdentifier(for:))
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        logger.info("Daily reminder cancelled")
    }

    func scheduleCashflowScheduledReminders(for transactions: [CashflowTransaction]) async {
        let reminders = buildScheduledReminderPayloads(from: transactions)
        if reminders.isEmpty {
            cancelCashflowScheduledReminders()
            return
        }

        let authorized = await requestAuthorization()
        guard authorized else {
            logger.warning("Skipping scheduled cashflow reminders: authorization not granted")
            return
        }

        cancelCashflowScheduledReminders()

        var createdIdentifiers: [String] = []
        for payload in reminders {
            let content = UNMutableNotificationContent()
            content.title = "millio"
            content.body = payload.body
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: payload.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: payload.identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await notificationCenter.add(request)
                createdIdentifiers.append(payload.identifier)
            } catch {
                logger.error("Failed to schedule cashflow reminder \(payload.identifier): \(error.localizedDescription)")
            }
        }

        defaults.set(createdIdentifiers, forKey: scheduledReminderIDsKey)
        logger.info("Scheduled cashflow reminders updated: \(createdIdentifiers.count)")
    }

    func cancelCashflowScheduledReminders() {
        let identifiers = defaults.stringArray(forKey: scheduledReminderIDsKey) ?? []
        guard !identifiers.isEmpty else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        defaults.set([], forKey: scheduledReminderIDsKey)
    }
    
    // MARK: - Private Methods

    private func makeTrigger(for settings: DailyReminderSettings) -> UNCalendarNotificationTrigger? {
        var components = DateComponents()
        components.hour = settings.hour
        components.minute = settings.minute

        switch settings.cadence {
        case .daily:
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .monthly:
            components.day = settings.dayOfMonth
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .once:
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: settings.selectedDate)
            components.year = dateComponents.year
            components.month = dateComponents.month
            components.day = dateComponents.day

            guard let fireDate = calendar.date(from: components), fireDate > now() else {
                return nil
            }
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
    }

    private struct ScheduledReminderPayload {
        let identifier: String
        let fireDate: Date
        let body: String
    }

    private func buildScheduledReminderPayloads(from transactions: [CashflowTransaction]) -> [ScheduledReminderPayload] {
        let referenceNow = now()
        let horizonEnd = calendar.date(byAdding: .day, value: 45, to: referenceNow) ?? referenceNow

        return transactions.compactMap { transaction in
            guard transaction.transactionType == .income || transaction.transactionType == .expense else {
                return nil
            }

            let plannedDate: Date
            if transaction.isRecurringTemplate {
                guard let next = nextOccurrenceDate(for: transaction, relativeTo: referenceNow) else { return nil }
                plannedDate = next
            } else {
                guard transaction.transactionDate > referenceNow else { return nil }
                plannedDate = transaction.transactionDate
            }

            let reminderDate = normalizedReminderDate(for: plannedDate)
            guard reminderDate > referenceNow, reminderDate <= horizonEnd else { return nil }
            let reminderLanguage = LocalizationSupport.resolvedLanguage(
                for: languageProvider(),
                fallbackLocale: .autoupdatingCurrent
            )
            let localizationLocale = LocalizationSupport.resolvedLocale(
                for: reminderLanguage,
                fallbackLocale: .autoupdatingCurrent
            )
            let baseMessage = scheduledReminderMessage(
                for: transaction,
                reminderDate: reminderDate,
                language: reminderLanguage,
                locale: localizationLocale
            )

            let identitySource = transaction.recurrenceSeriesID ?? transaction.transactionUniqueID
            let identifier = "\(Self.scheduledReminderIdentifierPrefix)|\(identitySource)|\(Int(reminderDate.timeIntervalSince1970))"
            return ScheduledReminderPayload(identifier: identifier, fireDate: reminderDate, body: baseMessage)
        }
    }

    private func nextOccurrenceDate(for transaction: CashflowTransaction, relativeTo referenceDate: Date) -> Date? {
        guard transaction.isRecurringTemplate else { return nil }
        guard let monthInterval = transaction.recurrenceRule.monthInterval else { return nil }

        let baseline = calendar.startOfDay(for: referenceDate)
        let templateDate = calendar.startOfDay(for: transaction.transactionDate)
        let templateMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: templateDate)) ?? templateDate
        let anchorDay = calendar.component(.day, from: transaction.transactionDate)
        var occurrenceIndex = 0

        while let targetMonthStart = calendar.date(
            byAdding: .month,
            value: monthInterval * occurrenceIndex,
            to: templateMonthStart
        ) {
            let candidate = makeMonthlyDate(monthStart: targetMonthStart, day: anchorDay)
            if candidate > baseline {
                return candidate
            }
            occurrenceIndex += 1
        }

        return nil
    }

    private func makeMonthlyDate(monthStart: Date, day: Int) -> Date {
        let daysRange = calendar.range(of: .day, in: .month, for: monthStart) ?? (1..<29)
        let minDay = daysRange.lowerBound
        let maxDay = daysRange.upperBound - 1
        let clampedDay = min(max(day, minDay), maxDay)
        return calendar.date(byAdding: .day, value: clampedDay - 1, to: monthStart) ?? monthStart
    }

    private func normalizedReminderDate(for plannedDate: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: plannedDate)
        var normalized = DateComponents()
        normalized.year = components.year
        normalized.month = components.month
        normalized.day = components.day
        normalized.hour = 9
        normalized.minute = 0
        return calendar.date(from: normalized) ?? plannedDate
    }

    private func scheduledReminderMessage(
        for transaction: CashflowTransaction,
        reminderDate: Date,
        language: Language,
        locale: Locale
    ) -> String {
        let dateText = formattedDate(reminderDate, locale: locale)

        switch language {
        case .russian:
            let kind: String = {
                switch transaction.transactionType {
                case .income: return "доход"
                case .expense: return "расход"
                default: return ""
                }
            }()

            return transaction.isRecurringTemplate
                ? "Напоминание: регулярный \(kind) запланирован на \(dateText)."
                : "Напоминание: запланированный \(kind) на \(dateText)."
        case .simplifiedChinese:
            let kind: String = {
                switch transaction.transactionType {
                case .income: return "收入"
                case .expense: return "支出"
                default: return ""
                }
            }()

            return transaction.isRecurringTemplate
                ? "提醒：周期性\(kind)计划于\(dateText)。"
                : "提醒：计划\(kind)时间为\(dateText)。"
        case .system, .english:
            let kind: String = {
                switch transaction.transactionType {
                case .income: return "income"
                case .expense: return "expense"
                default: return ""
                }
            }()

            return transaction.isRecurringTemplate
                ? "Reminder: recurring \(kind) is due on \(dateText)."
                : "Reminder: planned \(kind) is due on \(dateText)."
        }
    }

    private func formattedDate(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Deposit Maturity Notifications (Phase 9)

    private static let depositNotificationPrefix = "deposit_maturity_"

    func scheduleDepositMaturityNotification(
        identifier: String,
        investmentName: String,
        endDate: Date,
        daysBefore: Int,
        fireDate: Date
    ) async {
        let authorized = await requestAuthorization()
        guard authorized else { return }

        let notifID = Self.depositNotificationPrefix + identifier
        let content = UNMutableNotificationContent()
        content.title = L("finances.deposit.notification.title", defaultValue: "millio")
        let locale = Locale.current
        let formattedEnd = formattedDate(endDate, locale: locale)
        content.body = String(format: String(
            localized: "finances.deposit.notification.body",
            defaultValue: "Вклад «%@» заканчивается через %d дн. (%@)"
        ), investmentName, daysBefore, formattedEnd)
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: notifID, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
            logger.info("Scheduled deposit maturity notification for \(identifier) at \(fireDate)")
        } catch {
            logger.error("Failed to schedule deposit notification: \(error.localizedDescription)")
        }
    }

    func cancelDepositMaturityNotification(for identifier: String) {
        let notifID = Self.depositNotificationPrefix + identifier
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notifID])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [notifID])
    }
}
