//
//  CalendarRangeMonthView.swift
//  millio
//
//  Компонент календаря для выбора диапазона дат.
//  Поддерживает визуальное выделение выбранного периода.
//

import SwiftUI

enum CalendarRangeSelectionEndpoint {
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

private extension Color {
    static func calendarThemeRGB(_ red: Double, _ green: Double, _ blue: Double, opacity: Double = 1) -> Color {
        // A tiny midpoint bias keeps UIColor(self).getRed() from truncating the
        // intended 8-bit component one step lower in snapshot/unit tests.
        Color(
            .sRGB,
            red: (red + 0.5) / 255,
            green: (green + 0.5) / 255,
            blue: (blue + 0.5) / 255,
            opacity: opacity
        )
    }
}

enum CalendarRangeTheme {
    case neutral
    case cashflow
    case finances
    case cashback

    var accentColors: [Color] {
        switch self {
        case .neutral:
            return [AppColors.brandPrimary, AppColors.brandPrimary.opacity(0.72)]
        case .cashflow:
            return AppColors.cashflowGradient
        case .finances:
            return AppColors.financesGradient
        case .cashback:
            return [Color(hex: "1D76FF"), Color(hex: "0B56D8")]
        }
    }

    var panelFill: LinearGradient {
        switch self {
        case .neutral:
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.07),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cashflow:
            return LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.11).opacity(0.72),
                    Color(red: 0.03, green: 0.05, blue: 0.08).opacity(0.56)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .finances:
            return LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.12).opacity(0.70),
                    Color(red: 0.03, green: 0.05, blue: 0.08).opacity(0.54)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cashback:
            return LinearGradient(
                colors: [
                    Color(hex: "0B0F19").opacity(0.98),
                    Color(hex: "070B13").opacity(0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var panelStroke: LinearGradient {
        switch self {
        case .cashback:
            return LinearGradient(
                colors: [
                    Color(hex: "144AA8").opacity(0.62),
                    Color.white.opacity(0.05),
                    Color(hex: "0E2C62").opacity(0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [
                    accentColors.first?.opacity(0.34) ?? Color.white.opacity(0.14),
                    Color.white.opacity(0.06),
                    accentColors.last?.opacity(0.18) ?? Color.white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var accentFill: LinearGradient {
        LinearGradient(
            colors: accentColors.map { $0.opacity(0.95) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var softAccentFill: LinearGradient {
        LinearGradient(
            colors: accentColors.map { $0.opacity(0.22) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var accentShadow: Color {
        accentColors.first?.opacity(0.30) ?? Color.white.opacity(0.16)
    }

    var ringColor: Color {
        switch self {
        case .cashflow:
            return .calendarThemeRGB(60, 111, 196)
        case .finances:
            return .calendarThemeRGB(60, 111, 196)
        case .cashback:
            return .calendarThemeRGB(29, 118, 255)
        default:
            return accentColors.first?.opacity(0.92) ?? AppColors.textPrimary.opacity(0.82)
        }
    }

    var secondaryRingColor: Color {
        switch self {
        case .cashflow:
            return .calendarThemeRGB(46, 90, 157)
        case .finances:
            return .calendarThemeRGB(46, 90, 157)
        case .cashback:
            return .calendarThemeRGB(20, 85, 197)
        default:
            return accentColors.first?.opacity(0.42) ?? AppColors.textPrimary.opacity(0.24)
        }
    }

    var monthButtonFill: Color {
        switch self {
        case .cashback:
            return Color.white.opacity(0.05)
        default:
            return Color.white.opacity(0.06)
        }
    }

    var monthButtonStroke: Color {
        switch self {
        case .cashback:
            return Color.white.opacity(0.08)
        default:
            return Color.white.opacity(0.10)
        }
    }

    var dayCellFill: Color {
        switch self {
        case .cashback:
            return Color(hex: "0A0E16").opacity(0.96)
        default:
            return Color.white.opacity(0.015)
        }
    }

    var inactiveDayStroke: Color {
        switch self {
        case .cashflow, .finances:
            return Color.white.opacity(0.12)
        case .cashback:
            return Color(hex: "1455C5").opacity(0.90)
        default:
            return Color.white.opacity(0.10)
        }
    }

    var disabledDayStroke: Color {
        switch self {
        case .cashback:
            return Color.white.opacity(0.03)
        default:
            return Color.white.opacity(0.04)
        }
    }

    var disabledDayOpacity: Double {
        switch self {
        case .cashback:
            return 0.18
        default:
            return 0.34
        }
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
        // App calendars always start on Monday regardless of locale.
        (calendar.component(.weekday, from: monthStart) + 5) % 7
    }

    static func orderedWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return Array(symbols.dropFirst()) + [symbols[0]]
    }
}

/// Компонент календаря для выбора диапазона дат
struct CalendarRangeMonthView: View {

    // MARK: - Bindings

    @Binding var startDate: Date
    @Binding var endDate: Date
    var activeEndpoint: Binding<CalendarRangeSelectionEndpoint>? = nil
    var theme: CalendarRangeTheme = .neutral
    var highlightsSingleDaySelection: Bool = true

    // MARK: - State

    @State private var currentMonthAnchor: Date = Calendar.current.startOfDay(for: Date())

    // MARK: - Computed Properties

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Проверка, что дата в будущем
    private func isFuture(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) > today
    }

    /// Интервал текущего месяца
    private var monthInterval: DateInterval {
        CalendarRangeMonthLayout.monthInterval(for: currentMonthAnchor, calendar: Calendar.current)
    }

    /// Все дни текущего месяца
    private func daysInMonth() -> [Date] {
        CalendarRangeMonthLayout.daysInMonth(for: currentMonthAnchor, calendar: Calendar.current)
    }

    /// Проверка, входит ли дата в выбранный диапазон
    private func isInRange(_ date: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: min(startDate, endDate))
        let end = cal.startOfDay(for: max(startDate, endDate))
        let d = cal.startOfDay(for: date)
        return d >= start && d <= end
    }

    /// Проверка, что две даты — один и тот же день
    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                monthButton(systemName: "chevron.left", action: previousMonth)

                Spacer(minLength: 16)

                VStack(spacing: 4) {
                    Text(monthTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(selectionSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .multilineTextAlignment(.center)

                Spacer(minLength: 16)

                monthButton(systemName: "chevron.right", action: nextMonth)
                    .opacity(canMoveForward ? 1 : 0.4)
                    .disabled(!canMoveForward)
            }

            let orderedSymbols = CalendarRangeMonthLayout.orderedWeekdaySymbols(calendar: Calendar.current)
            HStack(spacing: 8) {
                ForEach(orderedSymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let cal = Calendar.current
            let firstDay = daysInMonth().first ?? currentMonthAnchor
            let weekdayOfFirst = CalendarRangeMonthLayout.leadingPlaceholderCount(for: firstDay, calendar: cal)
            let days = daysInMonth()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
                ForEach(0..<weekdayOfFirst, id: \.self) { _ in
                    Color.clear.frame(height: 50)
                }

                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(theme.panelStroke, lineWidth: 1)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .onAppear {
            let cal = Calendar.current
            let anchor = max(startDate, endDate)
            currentMonthAnchor = cal.startOfDay(for: anchor)
        }
        .onChange(of: startDate) { _, _ in
            updateAnchor()
        }
        .onChange(of: endDate) { _, _ in
            updateAnchor()
        }
    }

    // MARK: - Private Methods

    private func updateAnchor() {
        let cal = Calendar.current
        let anchor = max(startDate, endDate)
        currentMonthAnchor = cal.startOfDay(for: anchor)
    }

    private var selectionSummary: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d MMM")

        let start = min(startDate, endDate)
        let end = max(startDate, endDate)
        if isSameDay(start, end) {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: currentMonthAnchor).capitalized(with: formatter.locale)
    }

    private var canMoveForward: Bool {
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonthAnchor) else {
            return false
        }
        let nextStart = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) ?? nextMonth
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        return nextStart <= currentMonthStart
    }

    private func previousMonth() {
        if let prev = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthAnchor) {
            currentMonthAnchor = prev
        }
    }

    private func nextMonth() {
        guard canMoveForward,
              let next = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthAnchor) else {
            return
        }
        currentMonthAnchor = next
    }

    private func monthButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(theme.monthButtonFill)
                .overlay(
                    Circle()
                        .stroke(theme.monthButtonStroke, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                )
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let disabled = isFuture(day)
        let selected = isInRange(day)
        let isStart = isSameDay(day, min(startDate, endDate))
        let isEnd = isSameDay(day, max(startDate, endDate))
        let dayText = "\(Calendar.current.component(.day, from: day))"
        let same = isSameDay(startDate, endDate)
        let hasVisibleSelection = !same || highlightsSingleDaySelection
        let isEdge = hasVisibleSelection && ((same && isStart) || (!same && (isStart || isEnd)))
        let inMiddle = hasVisibleSelection && selected && !isEdge
        let isToday = isSameDay(day, today)

        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(theme.dayCellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(baseCellStroke(inMiddle: inMiddle, disabled: disabled), lineWidth: 1)
                )

            if inMiddle {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(theme.secondaryRingColor, lineWidth: 1.2)
            }

            if isEdge {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(theme.ringColor, lineWidth: 1.8)
                    .background(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            } else if isToday && hasVisibleSelection {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(theme.ringColor.opacity(0.72), lineWidth: 1.2)
            }

            Text(dayText)
                .font(.system(size: 18, weight: isEdge ? .semibold : .medium))
                .foregroundStyle(dayTextColor(disabled: disabled, inMiddle: inMiddle, isEdge: isEdge))
        }
        .opacity(disabled ? theme.disabledDayOpacity : 1.0)
        .frame(height: 50)
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .onTapGesture {
            guard !disabled else { return }
            let nextSelection = CalendarRangeSelectionLogic.applyTap(
                on: day,
                startDate: startDate,
                endDate: endDate,
                activeEndpoint: activeEndpoint?.wrappedValue
            )
            startDate = nextSelection.startDate
            endDate = nextSelection.endDate
            if let nextEndpoint = nextSelection.nextEndpoint {
                activeEndpoint?.wrappedValue = nextEndpoint
            }
            currentMonthAnchor = Calendar.current.startOfDay(for: day)
        }
    }

    private func baseCellStroke(inMiddle: Bool, disabled: Bool) -> Color {
        if inMiddle {
            return theme.secondaryRingColor.opacity(disabled ? 0.35 : 0.9)
        }
        return disabled ? theme.disabledDayStroke : theme.inactiveDayStroke
    }

    private func dayTextColor(disabled: Bool, inMiddle: Bool, isEdge: Bool) -> Color {
        if disabled {
            return AppColors.textPrimary.opacity(0.18)
        }
        if isEdge {
            return AppColors.textPrimary
        }
        if inMiddle {
            return AppColors.textPrimary.opacity(0.92)
        }
        return AppColors.textPrimary.opacity(0.84)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        @State private var end = Date()

        var body: some View {
            CalendarRangeMonthView(startDate: $start, endDate: $end, theme: .cashflow)
                .padding()
                .background(Color.black)
        }
    }

    return PreviewWrapper()
}
