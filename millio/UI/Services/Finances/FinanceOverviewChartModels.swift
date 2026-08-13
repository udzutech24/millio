//
//  FinanceOverviewChartModels.swift
//  millio
//
//  Модели для overview-блока финансов:
//  1) period chart debit / credit / saldo
//  2) бухгалтерская T-account раскладка по счетам и группам
//

import Foundation

struct FinanceOverviewPeriodEntry: Identifiable, Equatable {
    let id: Date
    let date: Date
    let debit: Double
    let credit: Double
}

enum FinanceOverviewGranularity: String, CaseIterable, Identifiable {
    case year
    case month
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .year:
            return L("Year")
        case .month:
            return L("Month")
        case .week:
            return L("Week")
        }
    }
}

struct FinanceOverviewBar: Identifiable, Equatable {
    let id: Date
    let periodStart: Date
    let label: String
    let debit: Double
    let credit: Double
    let saldo: Double
    let isPlaceholder: Bool
}

struct FinanceOverviewPresentation: Equatable {
    let selectedPeriodStart: Date
    let bars: [FinanceOverviewBar]
    let selectedBar: FinanceOverviewBar
}

enum FinanceOverviewChartBuilder {
    private static let compactVisiblePeriodCount = 4

    static func makePresentation(
        entries: [FinanceOverviewPeriodEntry],
        granularity: FinanceOverviewGranularity,
        selectedPeriodStart: Date?,
        referenceDate: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> FinanceOverviewPresentation {
        makePresentation(
            entries: entries,
            granularity: granularity,
            selectedPeriodStart: selectedPeriodStart,
            referenceDate: referenceDate,
            maxVisiblePeriods: compactVisiblePeriodCount,
            calendar: calendar,
            locale: locale
        )
    }

    static func makeFullScreenPresentation(
        entries: [FinanceOverviewPeriodEntry],
        granularity: FinanceOverviewGranularity,
        selectedPeriodStart: Date?,
        referenceDate: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> FinanceOverviewPresentation {
        makePresentation(
            entries: entries,
            granularity: granularity,
            selectedPeriodStart: selectedPeriodStart,
            referenceDate: referenceDate,
            maxVisiblePeriods: nil,
            calendar: calendar,
            locale: locale
        )
    }

    static func periodStart(
        for date: Date,
        granularity: FinanceOverviewGranularity,
        calendar: Calendar = .current
    ) -> Date {
        switch granularity {
        case .year:
            let components = calendar.dateComponents([.year], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        case .week:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        }
    }

    static func offsetPeriod(
        _ date: Date,
        by value: Int,
        granularity: FinanceOverviewGranularity,
        calendar: Calendar = .current
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

    private static func makePresentation(
        entries: [FinanceOverviewPeriodEntry],
        granularity: FinanceOverviewGranularity,
        selectedPeriodStart: Date?,
        referenceDate: Date,
        maxVisiblePeriods: Int?,
        calendar: Calendar,
        locale: Locale
    ) -> FinanceOverviewPresentation {
        let grouped = Dictionary(grouping: entries) {
            periodStart(for: $0.date, granularity: granularity, calendar: calendar)
        }
        let currentPeriodStart = periodStart(
            for: referenceDate,
            granularity: granularity,
            calendar: calendar
        )
        let firstPeriod = grouped.keys.min() ?? currentPeriodStart
        let normalizedSelection = max(
            min(
                periodStart(
                    for: selectedPeriodStart ?? currentPeriodStart,
                    granularity: granularity,
                    calendar: calendar
                ),
                currentPeriodStart
            ),
            firstPeriod
        )

        let starts: [Date]
        if let maxVisiblePeriods, maxVisiblePeriods > 0 {
            let earliestVisible = offsetPeriod(
                currentPeriodStart,
                by: -(maxVisiblePeriods - 1),
                granularity: granularity,
                calendar: calendar
            )
            starts = (0..<maxVisiblePeriods).map { index in
                offsetPeriod(
                    earliestVisible,
                    by: index,
                    granularity: granularity,
                    calendar: calendar
                )
            }
        } else {
            starts = visiblePeriodStarts(
                from: firstPeriod,
                to: currentPeriodStart,
                granularity: granularity,
                calendar: calendar
            )
        }

        let bars = starts.map {
            makeBar(
                for: $0,
                grouped: grouped,
                granularity: granularity,
                calendar: calendar,
                locale: locale
            )
        }
        let selectedBar = bars.first(where: { $0.periodStart == normalizedSelection }) ?? bars.last ?? makeBar(
            for: currentPeriodStart,
            grouped: grouped,
            granularity: granularity,
            calendar: calendar,
            locale: locale
        )

        return FinanceOverviewPresentation(
            selectedPeriodStart: selectedBar.periodStart,
            bars: bars,
            selectedBar: selectedBar
        )
    }

    private static func visiblePeriodStarts(
        from start: Date,
        to end: Date,
        granularity: FinanceOverviewGranularity,
        calendar: Calendar
    ) -> [Date] {
        var result: [Date] = []
        var cursor = start

        while cursor <= end {
            result.append(cursor)
            let next = offsetPeriod(cursor, by: 1, granularity: granularity, calendar: calendar)
            if next <= cursor {
                break
            }
            cursor = next
        }

        return result.isEmpty ? [end] : result
    }

    private static func makeBar(
        for periodStart: Date,
        grouped: [Date: [FinanceOverviewPeriodEntry]],
        granularity: FinanceOverviewGranularity,
        calendar: Calendar,
        locale: Locale
    ) -> FinanceOverviewBar {
        let items = grouped[periodStart] ?? []
        let debit = items.reduce(0) { $0 + $1.debit }
        let credit = items.reduce(0) { $0 + $1.credit }

        return FinanceOverviewBar(
            id: periodStart,
            periodStart: periodStart,
            label: periodLabel(
                for: periodStart,
                granularity: granularity,
                calendar: calendar,
                locale: locale
            ),
            debit: debit,
            credit: credit,
            saldo: debit - credit,
            isPlaceholder: items.isEmpty
        )
    }

    private static func periodLabel(
        for date: Date,
        granularity: FinanceOverviewGranularity,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar

        switch granularity {
        case .year:
            formatter.dateFormat = "yyyy"
        case .month:
            formatter.dateFormat = "MMM''yy"
        case .week:
            formatter.dateFormat = "d MMM"
        }

        return formatter.string(from: date)
    }
}

// MARK: - Ledger Layout Models

enum FinanceOverviewLedgerSide: String, Equatable {
    case debit
    case credit

    var title: String {
        switch self {
        case .debit:
            return L("finances.overview.chart.debit")
        case .credit:
            return L("finances.overview.chart.credit")
        }
    }
}

struct FinanceOverviewLedgerSourceItem: Equatable {
    let groupID: String
    let groupName: String
    let groupColorHex: String?
    let accountID: String
    let accountName: String
    let accountIcon: String
    let customIconName: String?
    let customIconColor: String?
    let amount: Double
    let side: FinanceOverviewLedgerSide
}

struct FinanceOverviewLedgerAccount: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let customIconName: String?
    let customIconColor: String?
    let amount: Double
}

struct FinanceOverviewLedgerGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let colorHex: String?
    let total: Double
    let side: FinanceOverviewLedgerSide
    let accounts: [FinanceOverviewLedgerAccount]
}

struct FinanceOverviewLedgerSidePresentation: Equatable {
    let side: FinanceOverviewLedgerSide
    let total: Double
    let groups: [FinanceOverviewLedgerGroup]

    var accountCount: Int {
        groups.reduce(0) { $0 + $1.accounts.count }
    }
}

struct FinanceOverviewLedgerPresentation: Equatable {
    let debit: FinanceOverviewLedgerSidePresentation
    let credit: FinanceOverviewLedgerSidePresentation

    var saldo: Double {
        debit.total - credit.total
    }

    var maxSideTotal: Double {
        max(debit.total, credit.total, 1)
    }

    var hasData: Bool {
        debit.total > 0.01 || credit.total > 0.01
    }

    func sidePresentation(
        for side: FinanceOverviewLedgerSide
    ) -> FinanceOverviewLedgerSidePresentation {
        switch side {
        case .debit:
            return debit
        case .credit:
            return credit
        }
    }
}

enum FinanceOverviewLedgerBuilder {
    static func makePresentation(
        items: [FinanceOverviewLedgerSourceItem]
    ) -> FinanceOverviewLedgerPresentation {
        FinanceOverviewLedgerPresentation(
            debit: makeSidePresentation(side: .debit, items: items),
            credit: makeSidePresentation(side: .credit, items: items)
        )
    }

    private static func makeSidePresentation(
        side: FinanceOverviewLedgerSide,
        items: [FinanceOverviewLedgerSourceItem]
    ) -> FinanceOverviewLedgerSidePresentation {
        let sideItems = items.filter { $0.side == side && $0.amount > 0.01 }
        let grouped = Dictionary(grouping: sideItems, by: \.groupID)

        let groups = grouped.compactMap { groupID, groupItems -> FinanceOverviewLedgerGroup? in
            guard let sample = groupItems.first else { return nil }
            let accounts = groupItems
                .map {
                    FinanceOverviewLedgerAccount(
                        id: $0.accountID,
                        name: $0.accountName,
                        icon: $0.accountIcon,
                        customIconName: $0.customIconName,
                        customIconColor: $0.customIconColor,
                        amount: $0.amount
                    )
                }
                .sorted {
                    if abs($0.amount - $1.amount) > 0.01 {
                        return $0.amount > $1.amount
                    }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }

            return FinanceOverviewLedgerGroup(
                id: "\(side.rawValue)-\(groupID)",
                name: sample.groupName,
                colorHex: sample.groupColorHex,
                total: accounts.reduce(0) { $0 + $1.amount },
                side: side,
                accounts: accounts
            )
        }
        .sorted {
            if abs($0.total - $1.total) > 0.01 {
                return $0.total > $1.total
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return FinanceOverviewLedgerSidePresentation(
            side: side,
            total: groups.reduce(0) { $0 + $1.total },
            groups: groups
        )
    }
}

enum FinanceOverviewLedgerInteraction {
    static func toggledExpandedSide(
        current: FinanceOverviewLedgerSide?,
        tapped: FinanceOverviewLedgerSide
    ) -> FinanceOverviewLedgerSide? {
        current == tapped ? nil : tapped
    }
}

/// Не позволяет более старому async-reload перезаписать результат последнего запроса.
enum FinanceOverviewReloadPolicy {
    static func shouldPublish(requestGeneration: Int, latestGeneration: Int) -> Bool {
        requestGeneration == latestGeneration
    }
}
