import Foundation

enum CashflowStatementMonthMatch: Equatable {
    case matches
    case mismatch
    case invalidPeriod
}

enum CashflowStatementPeriodResolution: Equatable {
    case singleMonth(year: Int, month: Int)
    case multipleMonths
    case invalidPeriod

    func date(calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard case .singleMonth(let year, let month) = self else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
            .map { CashflowMonthSelectionPolicy.canonicalMonth($0, calendar: calendar) }
    }
}

enum CashflowStatementMonthPolicy {
    static func validate(
        periodFrom: String,
        periodTo: String,
        selectedMonth: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CashflowStatementMonthMatch {
        let resolution = resolve(periodFrom: periodFrom, periodTo: periodTo)
        guard case .singleMonth(let year, let month) = resolution,
              let selected = calendar.dateInterval(of: .month, for: selectedMonth) else {
            return resolution == .invalidPeriod ? .invalidPeriod : .mismatch
        }
        let selectedComponents = calendar.dateComponents([.year, .month], from: selected.start)
        return selectedComponents.year == year && selectedComponents.month == month ? .matches : .mismatch
    }

    static func resolve(periodFrom: String, periodTo: String) -> CashflowStatementPeriodResolution {
        var parsingCalendar = Calendar(identifier: .gregorian)
        parsingCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = parsingCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = parsingCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false

        guard let from = formatter.date(from: periodFrom), let to = formatter.date(from: periodTo), from <= to else {
            return .invalidPeriod
        }
        let fromComponents = parsingCalendar.dateComponents([.year, .month], from: from)
        let toComponents = parsingCalendar.dateComponents([.year, .month], from: to)
        guard let year = fromComponents.year, let month = fromComponents.month,
              year == toComponents.year, month == toComponents.month else {
            return .multipleMonths
        }
        return .singleMonth(year: year, month: month)
    }
}
