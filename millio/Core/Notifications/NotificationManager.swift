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
    private let dailyReminderIdentifier = "daily_reminder"
    
    // Дружелюбные сообщения для ежедневных напоминаний
    private let reminderMessages = [
        "Привет! Не забудь зафиксировать свои финансы сегодня 📊",
        "Привет! Время проверить свои финансовые цели 💰",
        "Привет! Как дела с финансами? Запиши сегодняшние траты 📝",
        "Добро пожаловать! Не забудь обновить свои финансовые данные ✨",
        "Привет! Время подумать о своих финансах и целях 🎯",
        "Привет! Проверь свои счета и транзакции сегодня 💳",
        "Привет! Не забудь записать свои доходы и расходы 📈",
        "Добро пожаловать! Время обновить свои финансовые планы 🌟",
        "Привет! Как твои финансовые цели? Проверь прогресс 🚀",
        "Привет! Не забудь зафиксировать важные финансовые операции 💎",
        "Привет! Время подвести итоги дня и записать финансы 📊",
        "Добро пожаловать! Проверь свои карты и счета сегодня 💳",
        "Привет! Не забудь обновить информацию о своих финансах ✨",
        "Привет! Время записать сегодняшние финансовые операции 📝",
        "Привет! Как дела? Проверь свои финансовые цели и прогресс 🎯"
    ]
    
    init(
        notificationCenter: any UserNotificationCenterProtocol = UNUserNotificationCenter.current(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.notificationCenter = notificationCenter
        self.now = now
        self.calendar = calendar
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
        if enabled {
            // Запрашиваем разрешение, если еще не получено
            let authorized = await requestAuthorization()
            guard authorized else {
                logger.warning("Notification authorization not granted")
                return
            }
            
            // Отменяем предыдущие уведомления
            cancelDailyReminder()
            
            // Создаем новое ежедневное уведомление
            let content = UNMutableNotificationContent()
            content.title = "millio"
            content.body = getRandomMessage()
            content.sound = .default
            content.badge = 1
            
            // Настраиваем триггер на каждый день в 20:00
            var dateComponents = DateComponents()
            dateComponents.hour = 20
            dateComponents.minute = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            
            let request = UNNotificationRequest(
                identifier: dailyReminderIdentifier,
                content: content,
                trigger: trigger
            )
            
            do {
                try await notificationCenter.add(request)
                logger.info("Daily reminder scheduled successfully")
            } catch {
                logger.error("Failed to schedule daily reminder: \(error.localizedDescription)")
            }
        } else {
            cancelDailyReminder()
        }
    }
    
    func cancelDailyReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [dailyReminderIdentifier])
        logger.info("Daily reminder cancelled")
    }
    
    // MARK: - Private Methods
    
    private func getRandomMessage() -> String {
        // Используем день месяца для выбора сообщения (чтобы было предсказуемо, но разнообразно)
        let day = calendar.component(.day, from: now())
        let index = day % reminderMessages.count
        return reminderMessages[index]
    }
}
