import Foundation

enum CashflowStatementMonthMatch: Equatable {
    case matches
    case mismatch
    case invalidPeriod
}

enum CashflowStatementMonthPolicy {
    static func validate(
        periodFrom: String,
        periodTo: String,
        selectedMonth: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CashflowStatementMonthMatch {
        var parsingCalendar = Calendar(identifier: .gregorian)
        parsingCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = parsingCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = parsingCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false

        guard let from = formatter.date(from: periodFrom),
              let to = formatter.date(from: periodTo),
              from <= to,
              let selected = calendar.dateInterval(of: .month, for: selectedMonth) else {
            return .invalidPeriod
        }
        let selectedComponents = calendar.dateComponents([.year, .month], from: selected.start)
        let fromComponents = parsingCalendar.dateComponents([.year, .month], from: from)
        let toComponents = parsingCalendar.dateComponents([.year, .month], from: to)
        return fromComponents.year == selectedComponents.year
            && fromComponents.month == selectedComponents.month
            && toComponents.year == selectedComponents.year
            && toComponents.month == selectedComponents.month
            ? .matches
            : .mismatch
    }
}
