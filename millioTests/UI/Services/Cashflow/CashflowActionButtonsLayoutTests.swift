//
//  CashflowActionButtonsLayoutTests.swift
//  millioTests
//
//  Created by Codex on 02.03.2026.
//

import Testing
import CoreGraphics
@testable import millio

struct CashflowActionButtonsLayoutTests {
    @Test("Компактный режим включается на узкой ширине кнопок")
    func compactModeForNarrowWidth() {
        #expect(CashflowActionButtonsLayout.shouldUseCompactMetrics(containerWidth: CGFloat(351)))
    }

    @Test("Компактный режим выключается на широкой ширине кнопок")
    func regularModeForWideWidth() {
        #expect(!CashflowActionButtonsLayout.shouldUseCompactMetrics(containerWidth: CGFloat(393)))
    }

    @Test("Граничная ширина не включает компактный режим")
    func thresholdWidthUsesRegularMode() {
        let widthAtThreshold = CashflowActionButtonsLayout.compactButtonWidthThreshold *
            CashflowActionButtonsLayout.buttonCount +
            CashflowActionButtonsLayout.buttonSpacing * (CashflowActionButtonsLayout.buttonCount - 1)
        #expect(!CashflowActionButtonsLayout.shouldUseCompactMetrics(containerWidth: widthAtThreshold))
    }
}
