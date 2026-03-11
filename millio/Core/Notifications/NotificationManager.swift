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
    
    init(
        notificationCenter: any UserNotificationCenterProtocol = UNUserNotificationCenter.current(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        languageProvider: @escaping () -> Language = { LanguageManager.shared.currentLanguage }
    ) {
        self.notificationCenter = notificationCenter
        self.now = now
        self.calendar = calendar
        self.languageProvider = languageProvider
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
}
