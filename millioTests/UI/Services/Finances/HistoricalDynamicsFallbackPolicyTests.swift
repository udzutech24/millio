import Foundation
import Testing
@testable import millio

struct HistoricalDynamicsFallbackPolicyTests {
    @Test("Incomplete structured refresh preserves a renderable compatibility graph")
    func emptyStructuredSeriesFallsBackToCompatibilityPoints() {
        let compatibility = [
            ChartDataPoint(date: .distantPast, value: 99_396_025, label: "Total"),
            ChartDataPoint(date: .now, value: 99_625_057, label: "Total")
        ]

        let result = HistoricalDynamicsFallbackPolicy.renderablePoints(
            structured: [],
            compatibility: compatibility
        )

        #expect(result.map(\.value) == [99_396_025, 99_625_057])
    }

    @Test("Complete structured series remains authoritative")
    func structuredPointsWinWhenAvailable() {
        let structured = [ChartDataPoint(date: .now, value: 42, label: "Total")]
        let result = HistoricalDynamicsFallbackPolicy.renderablePoints(
            structured: structured,
            compatibility: [ChartDataPoint(date: .distantPast, value: 10, label: "Total")]
        )

        #expect(result.map(\.value) == [42])
    }
}
