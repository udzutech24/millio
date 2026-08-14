import Foundation

/// Calendar-day policy for date-only planned transactions.
/// Today belongs to actual cashflow; a one-time plan starts at tomorrow's midnight.
struct CashflowPlannedDatePolicy {
    let calendar: Calendar

    func isOneTimePlanned(_ transactionDate: Date, relativeTo referenceDate: Date) -> Bool {
        transactionDate >= startOfTomorrow(relativeTo: referenceDate)
    }

    func startOfTomorrow(relativeTo referenceDate: Date) -> Date {
        let today = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
