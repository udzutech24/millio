//
//  CashflowInsightsChartModels.swift
//  millio
//
//  Модель представления для нового графика Cashflow:
//  агрегирует доходы/расходы по неделям, месяцам и годам.
//

import Foundation

struct CashflowConvertedTransaction: Identifiable, Equatable {
    let id: String
    let date: Date
    let income: Double
    let expense: Double
}

enum CashflowInsightsGranularity: String, CaseIterable, Identifiable {
    case year
    case month
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .year:
            return String(localized: "Year")
        case .month:
            return String(localized: "Month")
        case .week:
            return "Week"
        }
    }
}

struct CashflowInsightsBar: Identifiable, Equatable {
    let id: Date
    let periodStart: Date
    let label: String
    let income: Double
    let expense: Double
    let isPlaceholder: Bool
}

struct CashflowInsightsCardModel: Equatable {
    let title: String
    let amount: Double
    let comparisonText: String
    let delta: Double
    let deltaTone: CashflowValueTone
}

struct CashflowInsightsPresentation: Equatable {
    let selectedPeriodStart: Date
    let bars: [CashflowInsightsBar]
    let expenseCard: CashflowInsightsCardModel
    let incomeCard: CashflowInsightsCardModel
}

enum CashflowInsightsChartBuilder {
    private static let epsilon = 0.0000001
    private static let visiblePeriodCount = 4

    static func makePresentation(
        entries: [CashflowConvertedTransaction],
        granularity: CashflowInsightsGranularity,
        selectedPeriodStart: Date?,
        referenceDate: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> CashflowInsightsPresentation {
        let currentPeriodStart = periodStart(
            for: referenceDate,
            granularity: granularity,
            calendar: calendar
        )
        let grouped = groupedEntries(entries, granularity: granularity, calendar: calendar)
        let normalizedSelection = normalizedSelection(
            selectedPeriodStart: selectedPeriodStart,
            referenceDate: referenceDate,
            granularity: granularity,
            grouped: grouped,
            calendar: calendar
        )

        let earliestVisiblePeriod = offsetPeriod(
            currentPeriodStart,
            by: -(visiblePeriodCount - 1),
            granularity: granularity,
            calendar: calendar
        )
        let windowStart = earliestVisiblePeriod

        let bars = (0..<visiblePeriodCount).map { index -> CashflowInsightsBar in
            let start = offsetPeriod(
                windowStart,
                by: index,
                granularity: granularity,
                calendar: calendar
            )
            return makeBar(for: start, grouped: grouped, granularity: granularity, calendar: calendar, locale: locale)
        }

        return makePresentation(
            bars: bars,
            grouped: grouped,
            selectedPeriodStart: normalizedSelection,
            granularity: granularity,
            calendar: calendar,
            locale: locale
        )
    }

    static func makeFullScreenPresentation(
        entries: [CashflowConvertedTransaction],
        granularity: CashflowInsightsGranularity,
        selectedPeriodStart: Date?,
        referenceDate: Date,
        maxVisiblePeriods: Int? = nil,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> CashflowInsightsPresentation {
        let grouped = groupedEntries(entries, granularity: granularity, calendar: calendar)
        let rawSelection = normalizedSelection(
            selectedPeriodStart: selectedPeriodStart,
            referenceDate: referenceDate,
            granularity: granularity,
            grouped: grouped,
            calendar: calendar
        )
        let currentPeriodStart = periodStart(
            for: referenceDate,
            granularity: granularity,
            calendar: calendar
        )
        let normalizedSelection: Date
        let bars: [CashflowInsightsBar]

        if let maxVisiblePeriods, maxVisiblePeriods > 0 {
            let windowStart = offsetPeriod(
                currentPeriodStart,
                by: -(maxVisiblePeriods - 1),
                granularity: granularity,
                calendar: calendar
            )
            normalizedSelection = max(min(rawSelection, currentPeriodStart), windowStart)
            let starts = (0..<maxVisiblePeriods).map { index in
                offsetPeriod(windowStart, by: index, granularity: granularity, calendar: calendar)
            }
            bars = starts.map {
                makeBar(for: $0, grouped: grouped, granularity: granularity, calendar: calendar, locale: locale)
            }
        } else {
            normalizedSelection = rawSelection
            let starts = allVisiblePeriodStarts(
                grouped: grouped,
                selectedPeriodStart: normalizedSelection,
                referenceDate: referenceDate,
                granularity: granularity,
                maxVisiblePeriods: maxVisiblePeriods,
                calendar: calendar
            )
            bars = starts.map {
                makeBar(for: $0, grouped: grouped, granularity: granularity, calendar: calendar, locale: locale)
            }
        }

        return makePresentation(
            bars: bars,
            grouped: grouped,
            selectedPeriodStart: normalizedSelection,
            granularity: granularity,
            calendar: calendar,
            locale: locale
        )
    }

    private static func groupedEntries(
        _ entries: [CashflowConvertedTransaction],
        granularity: CashflowInsightsGranularity,
        calendar: Calendar
    ) -> [Date: [CashflowConvertedTransaction]] {
        Dictionary(grouping: entries) {
            periodStart(for: $0.date, granularity: granularity, calendar: calendar)
        }
    }

    private static func normalizedSelection(
        selectedPeriodStart: Date?,
        referenceDate: Date,
        granularity: CashflowInsightsGranularity,
        grouped: [Date: [CashflowConvertedTransaction]],
        calendar: Calendar
    ) -> Date {
        let currentPeriodStart = periodStart(
            for: referenceDate,
            granularity: granularity,
            calendar: calendar
        )
        let rawSelection = periodStart(
            for: selectedPeriodStart ?? referenceDate,
            granularity: granularity,
            calendar: calendar
        )
        let firstPeriod = firstAvailablePeriod(in: grouped) ?? currentPeriodStart
        return max(min(rawSelection, currentPeriodStart), firstPeriod)
    }

    private static func firstAvailablePeriod(
        in grouped: [Date: [CashflowConvertedTransaction]]
    ) -> Date? {
        grouped.keys.min()
    }

    private static func allVisiblePeriodStarts(
        grouped: [Date: [CashflowConvertedTransaction]],
        selectedPeriodStart: Date,
        referenceDate: Date,
        granularity: CashflowInsightsGranularity,
        maxVisiblePeriods: Int?,
        calendar: Calendar
    ) -> [Date] {
        let currentPeriodStart = periodStart(
            for: referenceDate,
            granularity: granularity,
            calendar: calendar
        )
        let firstPeriod = firstAvailablePeriod(in: grouped) ?? selectedPeriodStart
        var starts: [Date] = []
        var cursor = firstPeriod

        while cursor <= currentPeriodStart {
            starts.append(cursor)
            let next = offsetPeriod(cursor, by: 1, granularity: granularity, calendar: calendar)
            if next <= cursor { break }
            cursor = next
        }

        if starts.isEmpty {
            starts = [currentPeriodStart]
        }

        if let maxVisiblePeriods, maxVisiblePeriods > 0, starts.count > maxVisiblePeriods {
            return Array(starts.suffix(maxVisiblePeriods))
        }

        return starts
    }

    static func availableRange(
        entries: [CashflowConvertedTransaction],
        granularity: CashflowInsightsGranularity,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        let grouped = groupedEntries(entries, granularity: granularity, calendar: calendar)
        let currentPeriodStart = periodStart(
            for: referenceDate,
            granularity: granularity,
            calendar: calendar
        )
        let firstPeriod = firstAvailablePeriod(in: grouped) ?? currentPeriodStart
        return firstPeriod...currentPeriodStart
    }

    static func title(
        for periodStart: Date,
        granularity: CashflowInsightsGranularity,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch granularity {
        case .year:
            return label(for: periodStart, granularity: .year, calendar: calendar, locale: locale)
        case .month:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("LLLL y")
            return formatter.string(from: periodStart).capitalized(with: locale)
        case .week:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            let end = offsetPeriod(periodStart, by: 1, granularity: .week, calendar: calendar)
            let endDate = calendar.date(byAdding: .day, value: -1, to: end) ?? periodStart
            return "\(label(for: periodStart, granularity: .week, calendar: calendar, locale: locale)) · \(formatter.string(from: periodStart)) - \(formatter.string(from: endDate))"
        }
    }

    static func periodRange(
        for periodStart: Date,
        granularity: CashflowInsightsGranularity,
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        let start = calendar.startOfDay(for: periodStart)
        let nextStart: Date
        switch granularity {
        case .year:
            nextStart = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        case .month:
            nextStart = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        case .week:
            nextStart = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        }
        let endCandidate = calendar.date(byAdding: .day, value: -1, to: nextStart) ?? start
        let end = calendar.startOfDay(for: endCandidate)
        return start...max(start, end)
    }

    static func offsetSelection(
        _ periodStart: Date,
        by value: Int,
        granularity: CashflowInsightsGranularity,
        entries: [CashflowConvertedTransaction],
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let range = availableRange(
            entries: entries,
            granularity: granularity,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let candidate = offsetPeriod(periodStart, by: value, granularity: granularity, calendar: calendar)
        return max(min(candidate, range.upperBound), range.lowerBound)
    }

    private static func makeBar(
        for start: Date,
        grouped: [Date: [CashflowConvertedTransaction]],
        granularity: CashflowInsightsGranularity,
        calendar: Calendar,
        locale: Locale
    ) -> CashflowInsightsBar {
        let bucket = grouped[start] ?? []
        let income = bucket.reduce(0) { $0 + $1.income }
        let expense = bucket.reduce(0) { $0 + $1.expense }

        return CashflowInsightsBar(
            id: start,
            periodStart: start,
            label: label(for: start, granularity: granularity, calendar: calendar, locale: locale),
            income: income,
            expense: expense,
            isPlaceholder: bucket.isEmpty
        )
    }

    private static func makePresentation(
        bars: [CashflowInsightsBar],
        grouped: [Date: [CashflowConvertedTransaction]],
        selectedPeriodStart: Date,
        granularity: CashflowInsightsGranularity,
        calendar: Calendar,
        locale: Locale
    ) -> CashflowInsightsPresentation {
        let previousPeriodStart = offsetPeriod(
            selectedPeriodStart,
            by: -1,
            granularity: granularity,
            calendar: calendar
        )
        let selectedEntries = grouped[selectedPeriodStart] ?? []
        let previousEntries = grouped[previousPeriodStart] ?? []

        let currentExpense = selectedEntries.reduce(0) { $0 + $1.expense }
        let previousExpense = previousEntries.reduce(0) { $0 + $1.expense }
        let currentIncome = selectedEntries.reduce(0) { $0 + $1.income }
        let previousIncome = previousEntries.reduce(0) { $0 + $1.income }
        let previousLabel = label(for: previousPeriodStart, granularity: granularity, calendar: calendar, locale: locale)

        return CashflowInsightsPresentation(
            selectedPeriodStart: selectedPeriodStart,
            bars: bars,
            expenseCard: makeCard(
                title: String(localized: "Expense"),
                currentAmount: currentExpense,
                previousAmount: previousExpense,
                previousLabel: previousLabel,
                treatsGrowthAsPositive: false
            ),
            incomeCard: makeCard(
                title: String(localized: "Income"),
                currentAmount: currentIncome,
                previousAmount: previousIncome,
                previousLabel: previousLabel,
                treatsGrowthAsPositive: true
            )
        )
    }

    static func periodStart(
        for date: Date,
        granularity: CashflowInsightsGranularity,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        case .week:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
                return interval.start
            }
            return calendar.startOfDay(for: date)
        }
    }

    private static func offsetPeriod(
        _ date: Date,
        by value: Int,
        granularity: CashflowInsightsGranularity,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .year:
            return calendar.date(byAdding: .year, value: value, to: date) ?? date
        case .month:
            return calendar.date(byAdding: .month, value: value, to: date) ?? date
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: value, to: date) ?? date
        }
    }

    private static func label(
        for date: Date,
        granularity: CashflowInsightsGranularity,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        switch granularity {
        case .year:
            return String(calendar.component(.year, from: date))
        case .month:
            let monthFormatter = DateFormatter()
            monthFormatter.locale = locale
            monthFormatter.setLocalizedDateFormatFromTemplate("LLL")
            let month = monthFormatter.string(from: date).capitalized(with: locale)

            let yearFormatter = DateFormatter()
            yearFormatter.locale = locale
            yearFormatter.dateFormat = "yy"
            return "\(month)'\(yearFormatter.string(from: date))"
        case .week:
            return "W\(calendar.component(.weekOfYear, from: date))"
        }
    }

    private static func makeCard(
        title: String,
        currentAmount: Double,
        previousAmount: Double,
        previousLabel: String,
        treatsGrowthAsPositive: Bool
    ) -> CashflowInsightsCardModel {
        let delta = currentAmount - previousAmount
        let comparisonText: String

        if abs(delta) <= epsilon {
            comparisonText = "Как в \(previousLabel)"
        } else if delta > 0 {
            comparisonText = "Больше, чем в \(previousLabel)"
        } else {
            comparisonText = "Меньше, чем в \(previousLabel)"
        }

        let tone: CashflowValueTone
        if abs(delta) <= epsilon {
            tone = .neutral
        } else if treatsGrowthAsPositive {
            tone = delta > 0 ? .positive : .negative
        } else {
            tone = delta < 0 ? .positive : .negative
        }

        return CashflowInsightsCardModel(
            title: title,
            amount: currentAmount,
            comparisonText: comparisonText,
            delta: delta,
            deltaTone: tone
        )
    }
}
