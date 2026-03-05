import Foundation

struct FinanceBalanceDayKey: Hashable, Codable {
    let rawValue: String

    init(date: Date, calendar: Calendar = FinanceBalanceDayKey.localCalendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        rawValue = String(format: "%04d-%02d-%02d", year, month, day)
    }

    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
}

enum FinanceBalanceReviewFrequency: String, CaseIterable, Identifiable {
    case off
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

struct FinanceBalanceSnapshotValue: Codable, Equatable {
    var value: Double
    var currencyCode: String
    var title: String
    var groupName: String
    var accountTypeRaw: String
    var effectSign: Int
    var isUnknown: Bool
}

struct FinanceBalanceSnapshotStorePayload: Codable {
    var days: [String: [String: FinanceBalanceSnapshotValue]]
    var accountCurrency: [String: String]

    static let empty = FinanceBalanceSnapshotStorePayload(days: [:], accountCurrency: [:])
}

struct FinanceBalanceLiveAccount: Identifiable, Equatable {
    let id: String
    let accountTypeRaw: String
    let accountID: String
    let title: String
    let bankName: String
    let groupName: String
    let currencyCode: String
    let value: Double
    let effectSign: Int
}

struct FinanceBalanceAuditRow: Identifiable, Equatable {
    let id: String
    let accountTypeRaw: String
    let accountID: String
    let title: String
    let groupName: String
    let currencyCode: String
    let value: Double
    let effectSign: Int
    let hasDateSnapshot: Bool
    let isUnknown: Bool
    let sourceOrder: Int

    var normalizedValue: Double {
        let trimmedType = accountTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmedType == "credit" {
            return value > 0 ? -value : value
        }
        if effectSign < 0, value > 0 {
            return -value
        }
        return value
    }
}

struct FinanceBalanceAuditGroupTotal: Identifiable, Equatable {
    let id: String
    let groupName: String
    let total: Double
}

struct FinanceBalanceAuditCurrencyTotal: Identifiable, Equatable {
    let id: String
    let currencyCode: String
    let total: Double
}
