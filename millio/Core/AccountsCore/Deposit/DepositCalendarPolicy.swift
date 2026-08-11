import Foundation

/// Pure calendar boundary for deposit estimates. Persisted historical `AccountEvent.dayKey`
/// remains untouched; new read models use one explicitly injected timezone instead of process state.
struct DepositCalendarPolicy: Equatable, Sendable {
    enum DayCountConvention: Equatable, Sendable {
        case act365
        case unsupported(reasonCode: String)
    }

    let timeZoneIdentifier: String
    let dayCountConvention: DayCountConvention

    init(
        timeZone: TimeZone,
        dayCountConvention: DayCountConvention = .act365
    ) {
        self.timeZoneIdentifier = timeZone.identifier
        self.dayCountConvention = dayCountConvention
    }

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        return value
    }

    func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func wholeDays(from start: Date, to end: Date) -> Int? {
        guard dayCountConvention == .act365 else { return nil }
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    func monthAnniversary(_ month: Int, after openingDate: Date) -> Date? {
        calendar.date(byAdding: .month, value: month, to: openingDate)
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func daysRemaining(from asOf: Date, to maturity: Date) -> Int {
        max(0, calendar.dateComponents(
            [.day], from: startOfDay(for: asOf), to: startOfDay(for: maturity)
        ).day ?? 0)
    }
}

