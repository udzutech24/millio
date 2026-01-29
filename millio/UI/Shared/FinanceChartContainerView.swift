//
//  FinanceChartContainerView.swift
//  millio
//
//  Переиспользуемый компонент графика для финансовых данных.
//  Поддерживает интерактивный выбор точки, аннотации и плавные анимации.
//

import SwiftUI
import Charts

// MARK: - Структура данных для шкалы Y

/// Параметры для расчета "красивой" шкалы Y
struct NiceYScale {
    let lower: Double
    let upper: Double
    let step: Double

    /// Создать NiceYScale на основе массива значений
    static func make(values: [Double], preferZeroBaseline: Bool = false) -> NiceYScale {
        guard var minV = values.min(), var maxV = values.max() else {
            return .init(lower: 0, upper: 1, step: 1)
        }

        if preferZeroBaseline {
            minV = min(0, minV)
            maxV = max(0, maxV)
        }

        if minV == maxV {
            let pad = max(1, abs(maxV) * 0.1)
            minV -= pad
            maxV += pad
        }

        let range = maxV - minV
        let targetTicks = 4.0
        let rawStep = range / targetTicks

        let pow10 = pow(10.0, floor(log10(rawStep)))
        let candidates: [Double] = [1, 2, 5, 10].map { $0 * pow10 }
        let step = candidates.first(where: { $0 >= rawStep }) ?? (10 * pow10)

        // Минимальный шаг 500К для больших сумм
        let magnitude = max(abs(minV), abs(maxV))
        let minStep: Double = (magnitude >= 1_000_000) ? 500_000 : step
        let finalStep = max(step, minStep)

        // Выровненные границы с отступом
        let baseLower = floor(minV / finalStep) * finalStep
        let baseUpper = ceil(maxV / finalStep) * finalStep
        let paddedLower = baseLower - finalStep
        let paddedUpper = baseUpper + finalStep

        return .init(lower: paddedLower, upper: paddedUpper, step: finalStep)
    }
}

// MARK: - Компонент графика

/// Переиспользуемый контейнер для отображения финансового графика
/// с поддержкой интерактивного выбора точки и аннотаций
struct FinanceChartContainerView: View {

    // MARK: - Входные параметры

    /// Точки данных для графика
    let points: [ChartDataPoint]

    /// Выбранная точка (nil = нет выбора)
    let selectedPoint: (date: Date, value: Double)?

    /// Цвет линии и области графика
    let seriesColor: Color

    /// Параметры шкалы Y
    let niceY: NiceYScale

    /// Диапазон X (даты)
    let xDomain: ClosedRange<Date>

    /// Шаг для меток X
    let xAxisStride: Calendar.Component

    /// Количество меток X
    let xAxisCount: Int

    /// Код валюты для форматирования
    let currencyCode: String

    /// Колбэк при выборе точки
    let onSelectPoint: ((Date, Double)?) -> Void

    // MARK: - Приватные методы

    /// Найти ближайший индекс точки по дате
    private func nearestIndex(for date: Date, in points: [ChartDataPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        var lo = 0
        var hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].date < date { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0 {
            let prev = points[lo - 1].date
            return abs(points[lo].date.timeIntervalSince(date)) < abs(prev.timeIntervalSince(date)) ? lo : (lo - 1)
        }
        return lo
    }

    /// Компактное форматирование суммы для оси Y
    private func formatCompact(_ value: Double) -> String {
        let absv = abs(value)
        let sign = value < 0 ? "−" : ""
        func fmt(_ x: Double) -> String {
            String(format: "%.1f", x).replacingOccurrences(of: ".0", with: "")
        }
        if absv >= 1_000_000_000 {
            return "\(sign)\(fmt(absv / 1_000_000_000)) млрд"
        }
        if absv >= 1_000_000 {
            return "\(sign)\(fmt(absv / 1_000_000)) млн"
        }
        if absv >= 1_000 {
            return "\(sign)\(fmt(absv / 1_000)) тыс"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    /// Форматирование суммы для аннотации
    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    // MARK: - Body

    var body: some View {
        Chart {
            // Область под графиком с градиентом
            ForEach(points) { item in
                AreaMark(
                    x: .value("Дата", item.date),
                    yStart: .value("Низ", niceY.lower),
                    yEnd: .value("Итого", item.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            seriesColor.opacity(0.28),
                            seriesColor.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Линия графика
                LineMark(
                    x: .value("Дата", item.date),
                    y: .value("Итого", item.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.0, lineJoin: .round))
                .foregroundStyle(seriesColor)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.clipped()
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: niceY.lower...niceY.upper)
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisStride, count: xAxisCount)) { value in
                AxisGridLine()
                    .foregroundStyle(AppColors.textTertiary.opacity(0.3))
                AxisTick()
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            let ticks = Array(stride(from: niceY.lower, through: niceY.upper, by: niceY.step))
            AxisMarks(position: .trailing, values: ticks) { value in
                AxisGridLine()
                    .foregroundStyle(AppColors.textTertiary.opacity(0.3))
                AxisTick()
                    .foregroundStyle(AppColors.textTertiary.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatCompact(v))
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack {
                    // Невидимая область для обработки жестов
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let plotFrame = geo[proxy.plotAreaFrame]
                                    guard plotFrame.contains(value.location) else { return }

                                    let xInPlot = value.location.x - plotFrame.minX
                                    if let date: Date = proxy.value(atX: xInPlot) {
                                        guard !points.isEmpty else { return }
                                        if let idx = nearestIndex(for: date, in: points) {
                                            let nearest = points[idx]
                                            onSelectPoint((nearest.date, nearest.value))
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    onSelectPoint(nil)
                                }
                        )

                    // Аннотация выбранной точки
                    if let sel = selectedPoint {
                        let plotFrame = geo[proxy.plotAreaFrame]
                        let xPos = proxy.position(forX: sel.date) ?? 0
                        let yPos = proxy.position(forY: sel.value) ?? 0

                        // Вертикальная пунктирная линия
                        Path { p in
                            p.move(to: CGPoint(x: xPos + plotFrame.minX, y: plotFrame.minY))
                            p.addLine(to: CGPoint(x: xPos + plotFrame.minX, y: plotFrame.maxY))
                        }
                        .stroke(
                            AppColors.textTertiary.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )

                        // Точка на графике
                        Circle()
                            .fill(seriesColor)
                            .frame(width: 8, height: 8)
                            .position(x: xPos + plotFrame.minX, y: yPos + plotFrame.minY)

                        // Bubble с информацией
                        let bubbleSize = CGSize(width: 140, height: 52)
                        let clampX = min(
                            max(xPos + plotFrame.minX, plotFrame.minX + bubbleSize.width / 2 + 6),
                            plotFrame.maxX - bubbleSize.width / 2 - 6
                        )
                        let clampY = min(
                            max(yPos + plotFrame.minY - 24, plotFrame.minY + bubbleSize.height / 2 + 6),
                            plotFrame.maxY - bubbleSize.height / 2 - 6
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sel.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("\(formatAmount(sel.value)) \(currencyCode)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.textTertiary.opacity(0.2))
                        )
                        .frame(width: bubbleSize.width, height: bubbleSize.height)
                        .position(x: clampX, y: clampY)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let samplePoints: [ChartDataPoint] = {
        let calendar = Calendar.current
        let today = Date()
        return (0..<30).map { day in
            let date = calendar.date(byAdding: .day, value: -day, to: today) ?? today
            let value = Double.random(in: 100_000...500_000)
            return ChartDataPoint(date: date, value: value, label: "Тест")
        }.reversed()
    }()

    let values = samplePoints.map { $0.value }
    let niceY = NiceYScale.make(values: values)
    let xDomain = (samplePoints.first?.date ?? Date())...(samplePoints.last?.date ?? Date())

    return FinanceChartContainerView(
        points: samplePoints,
        selectedPoint: nil,
        seriesColor: .orange,
        niceY: niceY,
        xDomain: xDomain,
        xAxisStride: .day,
        xAxisCount: 7,
        currencyCode: "RUB",
        onSelectPoint: { _ in }
    )
    .frame(height: 200)
    .padding()
    .background(Color.black)
}
