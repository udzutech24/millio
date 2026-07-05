import Foundation
import Testing
@testable import millio

/// Тесты чистой функции слияния графика старого мира с серией нового ядра (Фаза 1a-ui, AC3).
@Suite("ChartDataPoint.mergingNewCoreSeries")
struct ChartDataPointMergeTests {

    private func day(_ offset: Int, base: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Date {
        base.addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    @Test
    func emptyNewCoreSeriesIsNoOp() {
        let points = [ChartDataPoint(date: day(0), value: 100, label: "Total")]
        let merged = ChartDataPoint.mergingNewCoreSeries(points, newCoreSeries: [])
        #expect(merged.count == 1)
        #expect(merged[0].value == 100)
    }

    @Test
    func addsMatchingDayValuePointwise() {
        let points = [
            ChartDataPoint(date: day(0), value: 100, label: "Total"),
            ChartDataPoint(date: day(1), value: 110, label: "Total")
        ]
        let series: [(Date, Decimal)] = [(day(0), 50), (day(1), 60)]

        let merged = ChartDataPoint.mergingNewCoreSeries(points, newCoreSeries: series)
        #expect(merged[0].value == 150)
        #expect(merged[1].value == 170)
    }

    @Test
    func forwardFillsFromLastKnownDayWhenNoExactMatch() {
        // Старая точка приходится на день, которого нет в серии нового ядра напрямую (напр. дырка
        // старого графика на "важных датах") — берём последнее известное значение нового ядра.
        let points = [ChartDataPoint(date: day(2), value: 200, label: "Total")]
        let series: [(Date, Decimal)] = [(day(0), 10), (day(1), 20)]

        let merged = ChartDataPoint.mergingNewCoreSeries(points, newCoreSeries: series)
        #expect(merged[0].value == 220) // 200 + последнее известное (день 1) = 20
    }

    @Test
    func pointBeforeAnyNewCoreDataIsUnchanged() {
        let points = [ChartDataPoint(date: day(-5), value: 100, label: "Total")]
        let series: [(Date, Decimal)] = [(day(0), 999)]

        let merged = ChartDataPoint.mergingNewCoreSeries(points, newCoreSeries: series)
        #expect(merged[0].value == 100) // счёт ещё не существовал на эту дату — вклад 0
    }
}
