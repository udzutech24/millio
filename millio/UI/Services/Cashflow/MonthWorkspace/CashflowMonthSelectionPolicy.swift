import Foundation

enum CashflowMonthSelectionPolicy {
    static func canonicalMonth(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func offset(_ month: Date, by value: Int, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        calendar.date(byAdding: .month, value: value, to: canonicalMonth(month, calendar: calendar))
            .map { canonicalMonth($0, calendar: calendar) }
    }
}
