//
//  CalendarRangeMonthView.swift
//  millio
//
//  Shared range picker primitives used by Finances, Cashflow and History.
//  The picker intentionally mirrors the native "pick a period" mental model:
//  choose start, choose end, review the range, and apply it from the sheet.
//

import SwiftUI

enum CalendarRangeSelectionEndpoint: Equatable {
    case start
    case end
}

enum CalendarRangeSelectionLogic {
    static func applyTap(
        on tappedDate: Date,
        startDate: Date,
        endDate: Date,
        activeEndpoint: CalendarRangeSelectionEndpoint?,
        calendar: Calendar = .current
    ) -> (startDate: Date, endDate: Date, nextEndpoint: CalendarRangeSelectionEndpoint?) {
        let tapped = calendar.startOfDay(for: tappedDate)
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)

        if let activeEndpoint, calendar.isDate(start, inSameDayAs: end) {
            guard !calendar.isDate(tapped, inSameDayAs: start) else {
                return (start, end, activeEndpoint)
            }

            if tapped < start {
                return (tapped, end, .end)
            } else {
                return (start, tapped, .start)
            }
        }

        if let activeEndpoint {
            switch activeEndpoint {
            case .start:
                let clampedEnd = max(tapped, end)
                return (tapped, clampedEnd, .end)
            case .end:
                let clampedStart = min(start, tapped)
                return (clampedStart, tapped, .start)
            }
        }

        if calendar.isDate(start, inSameDayAs: end) {
            if tapped < start {
                return (tapped, end, nil)
            } else {
                return (start, tapped, nil)
            }
        }

        return (tapped, tapped, nil)
    }
}

struct CalendarRangeDayVisualState: Equatable {
    let showsFilledEdgeCircle: Bool
    let showsSelectedOutlineCircle: Bool
    let showsTodayOutlineCircle: Bool

    static func make(
        selected: Bool,
        isStart: Bool,
        isEnd: Bool,
        isSingleDay: Bool,
        highlightsSingleDaySelection: Bool,
        isToday: Bool
    ) -> CalendarRangeDayVisualState {
        let hasVisibleSelection = !isSingleDay || highlightsSingleDaySelection
        let showsFilledEdgeCircle = hasVisibleSelection && ((isSingleDay && isStart) || (!isSingleDay && (isStart || isEnd)))
        let showsSelectedOutlineCircle = selected && hasVisibleSelection && !showsFilledEdgeCircle
        let showsTodayOutlineCircle = isToday && !showsFilledEdgeCircle && !showsSelectedOutlineCircle

        return CalendarRangeDayVisualState(
            showsFilledEdgeCircle: showsFilledEdgeCircle,
            showsSelectedOutlineCircle: showsSelectedOutlineCircle,
            showsTodayOutlineCircle: showsTodayOutlineCircle
        )
    }
}

private extension Color {
    static func calendarThemeRGB(_ red: Double, _ green: Double, _ blue: Double, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: (red + 0.5) / 255,
            green: (green + 0.5) / 255,
            blue: (blue + 0.5) / 255,
            opacity: opacity
        )
    }
}

enum CalendarRangeTheme: Equatable {
    case neutral
    case cashflow
    case finances
    case cashback

    var accentColors: [Color] {
        switch self {
        case .neutral:
            return [AppColors.brandPrimary, AppColors.brandPrimary.opacity(0.76)]
        case .cashflow, .finances:
            return [Color.calendarThemeRGB(76, 139, 255), Color.calendarThemeRGB(46, 109, 224)]
        case .cashback:
            return [Color(hex: "4C8BFF"), Color(hex: "256FFF")]
        }
    }

    var panelFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.025),
                Color.white.opacity(0.015)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var panelStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.08),
                Color.white.opacity(0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var accentFill: LinearGradient {
        LinearGradient(
            colors: accentColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var softAccentFill: LinearGradient {
        LinearGradient(
            colors: accentColors.map { $0.opacity(0.18) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var accentShadow: Color {
        accentColors.first?.opacity(0.30) ?? Color.white.opacity(0.16)
    }

    var ringColor: Color {
        switch self {
        case .cashflow, .finances:
            return .calendarThemeRGB(60, 111, 196)
        case .cashback:
            return .calendarThemeRGB(29, 118, 255)
        case .neutral:
            return accentColors.first ?? AppColors.brandPrimary
        }
    }

    var secondaryRingColor: Color {
        switch self {
        case .cashflow, .finances:
            return .calendarThemeRGB(46, 90, 157)
        case .cashback:
            return .calendarThemeRGB(20, 85, 197)
        case .neutral:
            return (accentColors.first ?? AppColors.brandPrimary).opacity(0.55)
        }
    }

    var monthButtonFill: Color {
        Color.white.opacity(0.06)
    }

    var monthButtonStroke: Color {
        Color.white.opacity(0.10)
    }

    var dayCellFill: Color {
        .clear
    }

    var inactiveDayStroke: Color {
        Color.white.opacity(0.12)
    }

    var disabledDayStroke: Color {
        Color.white.opacity(0.04)
    }

    var disabledDayOpacity: Double {
        self == .cashback ? 0.18 : 0.34
    }

    var surfaceFill: Color {
        switch self {
        case .cashback:
            return Color(hex: "121720").opacity(0.92)
        default:
            return Color.white.opacity(0.05)
        }
    }

    var rangeStroke: Color {
        switch self {
        case .cashback:
            return Color(hex: "5D9BFF").opacity(0.70)
        default:
            return ringColor.opacity(0.64)
        }
    }

    var edgeHalo: Color {
        switch self {
        case .cashback:
            return Color(hex: "4C8BFF").opacity(0.22)
        default:
            return ringColor.opacity(0.18)
        }
    }
}

enum CalendarRangeQuickPreset: CaseIterable, Hashable {
    case today
    case last7Days
    case thisMonth
    case last30Days
    case last90Days
    case yearToDate

    func title(locale: Locale = .autoupdatingCurrent) -> String {
        let isRussian = locale.identifier.lowercased().hasPrefix("ru")
        switch self {
        case .today: return isRussian ? "Сегодня" : "Today"
        case .last7Days: return isRussian ? "7 дней" : "7 days"
        case .thisMonth: return isRussian ? "Месяц" : "Month"
        case .last30Days: return isRussian ? "30 дней" : "30 days"
        case .last90Days: return isRussian ? "90 дней" : "90 days"
        case .yearToDate: return isRussian ? "Год" : "Year"
        }
    }

    func dateRange(referenceDate: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: referenceDate)

        switch self {
        case .today:
            return (end, end)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
            return (start, end)
        case .thisMonth:
            let monthInterval = calendar.dateInterval(of: .month, for: end) ?? DateInterval(start: end, duration: 0)
            return (monthInterval.start, end)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: end) ?? end
            return (start, end)
        case .last90Days:
            let start = calendar.date(byAdding: .day, value: -89, to: end) ?? end
            return (start, end)
        case .yearToDate:
            let yearInterval = calendar.dateInterval(of: .year, for: end) ?? DateInterval(start: end, duration: 0)
            return (yearInterval.start, end)
        }
    }
}

enum CalendarRangePickerCopy {
    static func sheetTitle(locale: Locale = .autoupdatingCurrent) -> String {
        locale.identifier.lowercased().hasPrefix("ru") ? "Выберите период" : "Choose Period"
    }

    static func startDateLabel(locale: Locale = .autoupdatingCurrent) -> String {
        locale.identifier.lowercased().hasPrefix("ru") ? "Дата начала" : "Start date"
    }

    static func endDateLabel(locale: Locale = .autoupdatingCurrent) -> String {
        locale.identifier.lowercased().hasPrefix("ru") ? "Дата окончания" : "End date"
    }
}

enum CalendarRangeMonthLayout {
    static func monthInterval(for anchor: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .month, for: anchor) ?? DateInterval(start: anchor, duration: 0)
    }

    static func daysInMonth(for anchor: Date, calendar: Calendar) -> [Date] {
        let interval = monthInterval(for: anchor, calendar: calendar)
        var days: [Date] = []
        var day = interval.start
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    static func leadingPlaceholderCount(for monthStart: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: monthStart) + 5) % 7
    }

    static func orderedWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return Array(symbols.dropFirst()) + [symbols[0]]
    }

    static func monthRows(for anchor: Date, calendar: Calendar) -> [[Date?]] {
        let days = daysInMonth(for: anchor, calendar: calendar)
        let placeholders = Array(repeating: Optional<Date>.none, count: leadingPlaceholderCount(for: days.first ?? anchor, calendar: calendar))
        let cells = placeholders + days.map(Optional.some)
        var rows: [[Date?]] = []
        var index = 0

        while index < cells.count {
            var row = Array(cells[index..<min(index + 7, cells.count)])
            if row.count < 7 {
                row.append(contentsOf: Array(repeating: Optional<Date>.none, count: 7 - row.count))
            }
            rows.append(row)
            index += 7
        }

        return rows
    }

    static func visibleMonthAnchors(
        focusDate: Date,
        calendar: Calendar,
        monthsBack: Int = 24
    ) -> [Date] {
        let focusMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: focusDate)) ?? focusDate
        return stride(from: monthsBack - 1, through: 0, by: -1).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: focusMonth)
        }
    }
}

struct CalendarRangeMonthView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    var activeEndpoint: Binding<CalendarRangeSelectionEndpoint>? = nil
    var theme: CalendarRangeTheme = .neutral
    var highlightsSingleDaySelection: Bool = true

    @State private var focusMonthAnchor: Date = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { .current }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var monthAnchors: [Date] {
        CalendarRangeMonthLayout.visibleMonthAnchors(
            focusDate: max(startDate, endDate),
            calendar: calendar
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            let orderedSymbols = CalendarRangeMonthLayout.orderedWeekdaySymbols(calendar: calendar)
            HStack(spacing: 0) {
                ForEach(orderedSymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.92))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(monthAnchors, id: \.self) { monthAnchor in
                            monthSection(for: monthAnchor)
                                .id(monthAnchor)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .onAppear {
                    focusMonthAnchor = calendar.startOfDay(for: max(startDate, endDate))
                    scrollToFocusedMonth(proxy: proxy, animated: false)
                }
                .onChange(of: startDate) { _, _ in
                    focusMonthAnchor = calendar.startOfDay(for: max(startDate, endDate))
                    scrollToFocusedMonth(proxy: proxy, animated: true)
                }
                .onChange(of: endDate) { _, _ in
                    focusMonthAnchor = calendar.startOfDay(for: max(startDate, endDate))
                    scrollToFocusedMonth(proxy: proxy, animated: true)
                }
            }
            .frame(maxHeight: 470)
        }
    }

    private func scrollToFocusedMonth(proxy: ScrollViewProxy, animated: Bool) {
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: focusMonthAnchor)) ?? focusMonthAnchor
        guard monthAnchors.contains(month) else { return }
        let action = {
            proxy.scrollTo(month, anchor: .top)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.18), action)
        } else {
            action()
        }
    }

    private func monthSection(for anchor: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(monthTitle(for: anchor))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(theme.surfaceFill)
                )

            VStack(spacing: 8) {
                ForEach(Array(CalendarRangeMonthLayout.monthRows(for: anchor, calendar: calendar).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, day in
                            dayCell(day)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let normalizedDay = calendar.startOfDay(for: day)
            let disabled = normalizedDay > today
            let selected = isInRange(normalizedDay)
            let isStart = isSameDay(normalizedDay, min(startDate, endDate))
            let isEnd = isSameDay(normalizedDay, max(startDate, endDate))
            let isSingleDay = isSameDay(startDate, endDate)
            let visualState = CalendarRangeDayVisualState.make(
                selected: selected,
                isStart: isStart,
                isEnd: isEnd,
                isSingleDay: isSingleDay,
                highlightsSingleDaySelection: highlightsSingleDaySelection,
                isToday: isSameDay(normalizedDay, today)
            )
            let isEdge = visualState.showsFilledEdgeCircle

            ZStack {
                if visualState.showsFilledEdgeCircle {
                    Circle()
                        .fill(theme.accentFill)
                        .frame(width: 38, height: 38)
                        .shadow(color: theme.edgeHalo, radius: 10, y: 4)
                } else if visualState.showsSelectedOutlineCircle {
                    Circle()
                        .stroke(theme.rangeStroke, lineWidth: 1.15)
                        .frame(width: 38, height: 38)
                } else if visualState.showsTodayOutlineCircle {
                    Circle()
                        .stroke(theme.ringColor.opacity(selected ? 0 : 0.46), lineWidth: 1.2)
                        .frame(width: 36, height: 36)
                }

                Text("\(calendar.component(.day, from: normalizedDay))")
                    .font(.system(size: 18, weight: isEdge ? .semibold : .regular))
                        .foregroundStyle(dayTextColor(disabled: disabled, selected: selected, isEdge: isEdge))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
            .opacity(disabled ? theme.disabledDayOpacity : 1)
            .onTapGesture {
                guard !disabled else { return }
                let nextSelection = CalendarRangeSelectionLogic.applyTap(
                    on: normalizedDay,
                    startDate: startDate,
                    endDate: endDate,
                    activeEndpoint: activeEndpoint?.wrappedValue
                )
                startDate = nextSelection.startDate
                endDate = nextSelection.endDate
                if let nextEndpoint = nextSelection.nextEndpoint {
                    activeEndpoint?.wrappedValue = nextEndpoint
                }
                focusMonthAnchor = normalizedDay
            }
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
    }

    private func isInRange(_ date: Date) -> Bool {
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let end = calendar.startOfDay(for: max(startDate, endDate))
        let day = calendar.startOfDay(for: date)
        return day >= start && day <= end
    }

    private func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    private func dayTextColor(disabled: Bool, selected: Bool, isEdge: Bool) -> Color {
        if disabled {
            return AppColors.textPrimary.opacity(0.18)
        }
        if isEdge {
            return AppColors.textPrimary
        }
        if selected {
            return AppColors.textPrimary.opacity(0.96)
        }
        return AppColors.textPrimary.opacity(0.86)
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: date).capitalized(with: formatter.locale)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var start = Calendar.current.date(byAdding: .day, value: -21, to: Date()) ?? Date()
        @State private var end = Date()

        var body: some View {
            CalendarRangeMonthView(startDate: $start, endDate: $end, theme: .cashflow)
                .padding()
                .background(Color.black)
        }
    }

    return PreviewWrapper()
}
