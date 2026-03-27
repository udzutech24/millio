//
//  FinanceChartStyleTests.swift
//  millioTests
//
//  Проверяет, что график финансов остаётся плавным и визуально консистентным.
//

import CoreGraphics
import Testing
@testable import millio

struct FinanceChartStyleTests {
    @Test("Finance dynamics chart uses a smooth Apple-style curve")
    func usesSmoothCurve() {
        #expect(FinanceChartStyle.curve == .catmullRom)
    }

    @Test("Finance dynamics chart keeps the line prominent and the fill restrained")
    func usesBalancedLineAndAreaMetrics() {
        #expect(FinanceChartStyle.lineWidth == 2.4)
        #expect(FinanceChartStyle.areaTopOpacity < 0.3)
        #expect(FinanceChartStyle.areaMiddleOpacity < FinanceChartStyle.areaTopOpacity)
        #expect(FinanceChartStyle.areaBottomOpacity < FinanceChartStyle.areaMiddleOpacity)
        #expect(FinanceChartStyle.lineShadowRadius >= 12)
    }

    @Test("Selected point remains crisp and touch-friendly")
    func selectionMarkerUsesReadableSizing() {
        #expect(FinanceChartStyle.selectionOuterDiameter > FinanceChartStyle.selectionInnerDiameter)
        #expect(FinanceChartStyle.selectionRingLineWidth == 2)
        #expect(FinanceChartStyle.selectionOuterDiameter >= 12)
    }
}
