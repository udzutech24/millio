//
//  CalendarRangeMonthView.swift
//  millio
//
//  Компонент календаря для выбора диапазона дат.
//  Поддерживает визуальное выделение выбранного периода.
//

import SwiftUI

/// Компонент календаря для выбора диапазона дат
struct CalendarRangeMonthView: View {

    // MARK: - Bindings

    @Binding var startDate: Date
    @Binding var endDate: Date

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
        let cal = Calendar.current
        return cal.dateInterval(of: .month, for: currentMonthAnchor) ?? DateInterval(start: Date(), duration: 0)
    }

    /// Все дни текущего месяца
    private func daysInMonth() -> [Date] {
        let cal = Calendar.current
        let interval = monthInterval
        var days: [Date] = []
        var day = interval.start
        while day <= interval.end {
            days.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        // Убираем последний день (первый день следующего месяца)
        if let last = days.last, cal.component(.month, from: last) != cal.component(.month, from: interval.start) {
            _ = days.popLast()
        }
        return days
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
        VStack(spacing: 8) {
            // Заголовок с навигацией по месяцам
            HStack {
                Button {
                    if let prev = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthAnchor) {
                        currentMonthAnchor = prev
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(currentMonthAnchor, format: .dateTime.month(.wide).year())
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button {
                    if let next = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthAnchor) {
                        currentMonthAnchor = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            // Дни недели
            let symbols = Calendar.current.shortStandaloneWeekdaySymbols
            let orderedSymbols = rotateToStartOnMonday(symbols)
            HStack {
                ForEach(orderedSymbols, id: \.self) { s in
                    Text(s.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Сетка дней
            let cal = Calendar.current
            let firstDay = daysInMonth().first ?? currentMonthAnchor
            // Сдвиг: понедельник = 0
            let weekdayOfFirst = (cal.component(.weekday, from: firstDay) + 5) % 7
            let days = daysInMonth()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                // Пустые ячейки в начале
                ForEach(0..<weekdayOfFirst, id: \.self) { _ in
                    Color.clear.frame(height: 44)
                }

                // Дни месяца
                ForEach(days, id: \.self) { day in
                    let disabled = isFuture(day)
                    let selected = isInRange(day)
                    let isStart = isSameDay(day, min(startDate, endDate))
                    let isEnd = isSameDay(day, max(startDate, endDate))

                    ZStack {
                        // Фон выделения диапазона
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: AppColors.financesGradient.map { $0.opacity(0.2) },
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }

                        // Число дня
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.callout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(8)
                            .background(
                                Group {
                                    let same = isSameDay(startDate, endDate)
                                    if (same && isStart) || (!same && (isStart || isEnd)) {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: AppColors.financesGradient,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                            .foregroundStyle((isStart || isEnd) ? Color.white : AppColors.textPrimary)
                    }
                    .opacity(disabled ? 0.35 : 1.0)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !disabled else { return }
                        let tapped = day
                        let s = Calendar.current.startOfDay(for: startDate)
                        let e = Calendar.current.startOfDay(for: endDate)
                        if isSameDay(s, e) {
                            // Текущий выбор — одна дата: расширяем до tapped
                            if tapped < s {
                                startDate = tapped
                            } else {
                                endDate = tapped
                            }
                        } else {
                            // Диапазон уже выбран: начинаем новый выбор
                            startDate = tapped
                            endDate = tapped
                        }
                        currentMonthAnchor = Calendar.current.startOfDay(for: tapped)
                    }
                }
            }
        }
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

    /// Сдвигает массив дней недели, чтобы понедельник был первым
    private func rotateToStartOnMonday(_ symbols: [String]) -> [String] {
        guard symbols.count == 7 else { return symbols }
        // По умолчанию Swift начинает с воскресенья
        return Array(symbols.dropFirst()) + [symbols.first!]
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        @State private var end = Date()

        var body: some View {
            CalendarRangeMonthView(startDate: $start, endDate: $end)
                .padding()
                .background(Color.black)
        }
    }

    return PreviewWrapper()
}
