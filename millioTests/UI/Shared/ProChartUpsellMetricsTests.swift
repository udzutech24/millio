//
//  ProChartUpsellMetricsTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import CoreGraphics
import Testing
@testable import millio

@Suite("PRO chart upsell metrics")
struct ProChartUpsellMetricsTests {

    @Test("Compact metrics are smaller than regular")
    func testCompactSmallerThanRegular() {
        let compact = ProChartUpsellMetrics.make(for: .compact)
        let regular = ProChartUpsellMetrics.make(for: .regular)

        #expect(compact.iconPointSize < regular.iconPointSize)
        #expect(compact.titlePointSize < regular.titlePointSize)
        #expect(compact.subtitlePointSize < regular.subtitlePointSize)
        #expect(compact.ctaPointSize < regular.ctaPointSize)
        #expect(compact.ctaVerticalPadding < regular.ctaVerticalPadding)
    }

    @Test("Metrics are positive and finite")
    func testMetricsArePositiveAndFinite() {
        for size in [ProChartUpsellMetrics.Size.compact, .regular] {
            let metrics = ProChartUpsellMetrics.make(for: size)

            let values: [CGFloat] = [
                metrics.iconPointSize,
                metrics.titlePointSize,
                metrics.subtitlePointSize,
                metrics.ctaPointSize,
                metrics.verticalSpacing,
                metrics.ctaVerticalPadding
            ]

            #expect(values.allSatisfy { $0.isFinite && $0 > 0 })
        }
    }
}

