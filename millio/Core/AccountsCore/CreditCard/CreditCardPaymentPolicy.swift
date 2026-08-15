import Foundation

enum CreditCardPaymentDateMode: String, Codable, CaseIterable {
    case gracePeriod
    case exactDate
}

enum CreditCardReminderLead: Int, Codable, CaseIterable {
    case none = -1
    case dayOf = 0
    case oneDay = 1
    case threeDays = 3
    case sevenDays = 7
}

struct CreditCardPaymentSettings: Codable, Equatable {
    var mode: CreditCardPaymentDateMode = .gracePeriod
    var anchorDate: Date = Date()
    var exactDate: Date = Date()
    var reminderLead: CreditCardReminderLead = .none
    var reminderHour: Int = 10
    var reminderMinute: Int = 0
}

struct CreditCardPaymentStatus: Equatable {
    let dueDate: Date
    let daysRemaining: Int
    let isOverdue: Bool
}

enum CreditCardPaymentPolicy {
    static func dueDate(
        settings: CreditCardPaymentSettings,
        graceDays: Int?,
        calendar: Calendar
    ) -> Date? {
        switch settings.mode {
        case .exactDate:
            return calendar.startOfDay(for: settings.exactDate)
        case .gracePeriod:
            guard let graceDays, graceDays > 0 else { return nil }
            return calendar.date(byAdding: .day, value: graceDays, to: calendar.startOfDay(for: settings.anchorDate))
        }
    }

    static func status(
        settings: CreditCardPaymentSettings,
        graceDays: Int?,
        now: Date,
        calendar: Calendar
    ) -> CreditCardPaymentStatus? {
        guard let dueDate = dueDate(settings: settings, graceDays: graceDays, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: dueDate).day ?? 0
        return CreditCardPaymentStatus(dueDate: dueDate, daysRemaining: days, isOverdue: days < 0)
    }

    static func reminderDate(
        settings: CreditCardPaymentSettings,
        graceDays: Int?,
        calendar: Calendar
    ) -> Date? {
        guard settings.reminderLead != .none,
              let dueDate = dueDate(settings: settings, graceDays: graceDays, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: -settings.reminderLead.rawValue, to: dueDate) else {
            return nil
        }
        return calendar.date(bySettingHour: settings.reminderHour, minute: settings.reminderMinute, second: 0, of: shifted)
    }
}

struct CreditCardPaymentSettingsStore {
    private let defaults: UserDefaults
    private let keyPrefix = "credit_card_payment_settings."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load(accountID: UUID) -> CreditCardPaymentSettings? {
        guard let data = defaults.data(forKey: keyPrefix + accountID.uuidString) else { return nil }
        return try? JSONDecoder().decode(CreditCardPaymentSettings.self, from: data)
    }

    func save(_ settings: CreditCardPaymentSettings, accountID: UUID) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: keyPrefix + accountID.uuidString)
    }
}
