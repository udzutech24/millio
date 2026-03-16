//
//  CashflowHistorySummaryLayoutTests.swift
//  millioTests
//
//  Created by Codex on 16.03.2026.
//

import Testing
import CoreGraphics
@testable import millio

struct CashflowHistorySummaryLayoutTests {
    @Test("Summary использует плотную сетку по ширине экрана")
    func summaryUsesAdaptiveColumns() {
        #expect(CashflowHistorySummaryLayout.columnCount(containerWidth: 320) == 2)
        #expect(CashflowHistorySummaryLayout.columnCount(containerWidth: 390) == 3)
        #expect(CashflowHistorySummaryLayout.columnCount(containerWidth: 700) == 4)
    }

    @Test("Summary растет по высоте когда категорий становится больше")
    func summaryHeightGrowsWithEntries() {
        let compactHeight = CashflowHistorySummaryLayout.expandedHeight(
            containerWidth: 390,
            entryCount: 3
        )
        let denseHeight = CashflowHistorySummaryLayout.expandedHeight(
            containerWidth: 390,
            entryCount: 9
        )

        #expect(denseHeight > compactHeight)
        #expect(compactHeight > CashflowHistorySummaryLayout.collapsedHeight)
    }

    @Test("Коллапс summary ограничен диапазоном 0...1")
    func summaryCollapseProgressIsClamped() {
        #expect(CashflowHistorySummaryLayout.collapseProgress(minY: 24) == 0)
        #expect(CashflowHistorySummaryLayout.collapseProgress(minY: -CashflowHistorySummaryLayout.collapseDistance / 2) == 0.5)
        #expect(CashflowHistorySummaryLayout.collapseProgress(minY: -999) == 1)
    }

    @Test("Высота summary плавно уменьшается при скролле")
    func summaryContainerHeightInterpolatesToCollapsedState() {
        let expandedHeight = CashflowHistorySummaryLayout.containerHeight(
            containerWidth: 390,
            entryCount: 8,
            collapseProgress: 0
        )
        let collapsedHeight = CashflowHistorySummaryLayout.containerHeight(
            containerWidth: 390,
            entryCount: 8,
            collapseProgress: 1
        )

        #expect(expandedHeight > collapsedHeight)
        #expect(collapsedHeight == CashflowHistorySummaryLayout.collapsedHeight)
    }
}
