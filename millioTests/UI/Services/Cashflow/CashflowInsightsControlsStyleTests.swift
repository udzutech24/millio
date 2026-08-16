//
//  CashflowInsightsControlsStyleTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import CoreGraphics
import Testing
@testable import millio

struct CashflowInsightsControlsStyleTests {
    @Test("Compact chart reserves enough height for bar labels")
    func compactBarsHeightPreventsPickerOverlap() {
        #expect(CashflowInsightsControlsStyle.compactBarsHeight < 200)
        #expect(
            CashflowInsightsControlsStyle.compactLabelsAreaHeight
                >= CashflowInsightsControlsStyle.minimumCompactLabelsAreaHeight
        )
    }

    @Test("Full screen granularity picker is larger than compact")
    func fullScreenPickerHasLargerTouchTarget() {
        let compact = CashflowInsightsControlsStyle.granularityPickerMetrics(isFullScreen: false)
        let full = CashflowInsightsControlsStyle.granularityPickerMetrics(isFullScreen: true)

        #expect(full.fontSize > compact.fontSize)
        #expect(full.itemVerticalPadding > compact.itemVerticalPadding)
    }

    @Test("Compact granularity picker has usable touch target")
    func compactPickerHasUsableTouchTarget() {
        let compact = CashflowInsightsControlsStyle.granularityPickerMetrics(isFullScreen: false)

        #expect(compact.itemVerticalPadding >= 6)
        #expect(compact.containerPadding >= 2)
    }
}
