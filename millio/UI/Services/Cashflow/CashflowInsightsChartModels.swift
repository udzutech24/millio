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
        case .year:  return CashflowLocalization.periodYear
        case .month: return CashflowLocalization.periodMonth
        case .week:  return CashflowLocalization.periodWeek
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

enum CashflowInsightsMonthLabelStyle {
    case abbreviatedWithYear
    case monthNumber
}

enum CashflowInsightsChartBuilder {
    private static let epsilon = 0.0000001
    private static let visiblePeriodCount = 4

    /// Строит график и карточки сравнения для выбранного диапазона дат.
    /// - Cards: показывают сумму за выбранный диапазон и сравнение с предыдущим диапазоном той же длины.
    /// - Bars: агрегируют значения внутри диапазона по выбранной гранулярности.
    static func makePresentation(
        entries: [CashflowConvertedTransaction],
        dateRange: ClosedRange<Date>,
        granularity: CashflowInsightsGranularity,
        calendar: Calendar = .current,
        locale: Locale = AppLocalization.currentAppLocale
    ) -> CashflowInsightsPresentation {
        let startDay = calendar.startOfDay(for: dateRange.lowerBound)
        let endDay = calendar.startOfDay(for: dateRange.upperBound)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay

        let dayCount = max((calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1, 1)
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: startDay) ?? startDay
        let previousStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: previousEnd) ?? previousEnd
        let previousEndExclusive = calendar.date(byAdding: .day, value: 1, to: previousEnd) ?? previousEnd

        let currentEntries = entries.filter { $0.date >= startDay && $0.date < endExclusive }
        let previousEntries = entries.filter { $0.date >= previousStart && $0.date < previousEndExclusive }

        let currentIncome = currentEntries.reduce(0) { $0 + $1.income }
        let currentExpense = currentEntries.reduce(0) { $0 + $1.expense }
        let previousIncome = previousEntries.reduce(0) { $0 + $1.income }
        let previousExpense = previousEntries.reduce(0) { $0 + $1.expense }
        let previousLabel = rangeLabel(start: previousStart, end: previousEnd, calendar: calendar, locale: locale)

        let barPeriodStarts = periodStarts(
            in: startDay...endDay,
            granularity: granularity,
            calendar: calendar
        )
        let grouped = groupedEntries(currentEntries, granularity: granularity, calendar: calendar)
        let bars = barPeriodStarts.map { start in
            makeBar(for: start, grouped: grouped, granularity: granularity, calendar: calendar, locale: locale)
        }
        let selectedPeriodStart = barPeriodStarts.last
            ?? periodStart(for: endDay, granularity: granularity, calendar: calendar)

        return CashflowInsightsPresentation(
            selectedPeriodStart: selectedPeriodStart,
            bars: bars,
            expenseCard: makeCard(
                title: CashflowLocalization.typeExpense,
                currentAmount: currentExpense,
                previousAmount: previousExpense,
                previousLabel: previousLabel,
                treatsGrowthAsPositive: false
            ),
            incomeCard: makeCard(
                title: CashflowLocalization.typeIncome,
                currentAmount: currentIncome,
                previousAmount: previousIncome,
                previousLabel: previousLabel,
                treatsGrowthAsPositive: true
            )
        )
    }

    static func makePresentation(
        entries: [CashflowConvertedTransaction],
        granularity: CashflowInsightsGranularity,
        selectedPeriodStart: Date?,
        referenceDate: Date,
        calendar: Calendar = .current,
        locale: Locale = AppLocalization.currentAppLocale
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
        monthLabelStyle: CashflowInsightsMonthLabelStyle = .abbreviatedWithYear,
        calendar: Calendar = .current,
        locale: Locale = AppLocalization.currentAppLocale
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
                makeBar(
                    for: $0,
                    grouped: grouped,
                    granularity: granularity,
                    monthLabelStyle: monthLabelStyle,
                    calendar: calendar,
                    locale: locale
                )
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
                makeBar(
                    for: $0,
                    grouped: grouped,
                    granularity: granularity,
                    monthLabelStyle: monthLabelStyle,
                    calendar: calendar,
                    locale: locale
                )
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
        locale: Locale = AppLocalization.currentAppLocale
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
        monthLabelStyle: CashflowInsightsMonthLabelStyle = .abbreviatedWithYear,
        calendar: Calendar,
        locale: Locale
    ) -> CashflowInsightsBar {
        let bucket = grouped[start] ?? []
        let income = bucket.reduce(0) { $0 + $1.income }
        let expense = bucket.reduce(0) { $0 + $1.expense }

        return CashflowInsightsBar(
            id: start,
            periodStart: start,
            label: label(
                for: start,
                granularity: granularity,
                monthLabelStyle: monthLabelStyle,
                calendar: calendar,
                locale: locale
            ),
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
                title: CashflowLocalization.typeExpense,
                currentAmount: currentExpense,
                previousAmount: previousExpense,
                previousLabel: previousLabel,
                treatsGrowthAsPositive: false
            ),
            incomeCard: makeCard(
                title: CashflowLocalization.typeIncome,
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
        monthLabelStyle: CashflowInsightsMonthLabelStyle = .abbreviatedWithYear,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        switch granularity {
        case .year:
            return String(calendar.component(.year, from: date))
        case .month:
            if monthLabelStyle == .monthNumber {
                return String(calendar.component(.month, from: date))
            }
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
            comparisonText = "\(L("cashflow.insights.comparison.same_as")) \(previousLabel)"
        } else if delta > 0 {
            comparisonText = "\(L("cashflow.insights.comparison.more_than")) \(previousLabel)"
        } else {
            comparisonText = "\(L("cashflow.insights.comparison.less_than")) \(previousLabel)"
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

    private static func periodStarts(
        in dateRange: ClosedRange<Date>,
        granularity: CashflowInsightsGranularity,
        calendar: Calendar
    ) -> [Date] {
        let start = periodStart(for: dateRange.lowerBound, granularity: granularity, calendar: calendar)
        let end = periodStart(for: dateRange.upperBound, granularity: granularity, calendar: calendar)
        guard start <= end else { return [start] }

        var result: [Date] = []
        var cursor = start
        while cursor <= end {
            result.append(cursor)
            let next = offsetPeriod(cursor, by: 1, granularity: granularity, calendar: calendar)
            if next <= cursor { break }
            cursor = next
        }
        return result
    }

    private static func rangeLabel(
        start: Date,
        end: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let startYear = calendar.component(.year, from: startDay)
        let endYear = calendar.component(.year, from: endDay)

        let formatter = DateFormatter()
        formatter.locale = locale
        if startYear == endYear {
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            let startText = formatter.string(from: startDay)
            let endText = formatter.string(from: endDay)
            let yearText = String(endYear)
            return "\(startText) — \(endText), \(yearText)"
        }

        formatter.setLocalizedDateFormatFromTemplate("d MMM y")
        return "\(formatter.string(from: startDay)) — \(formatter.string(from: endDay))"
    }
}
