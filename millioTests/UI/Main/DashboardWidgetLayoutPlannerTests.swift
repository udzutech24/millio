//
//  DashboardWidgetLayoutPlannerTests.swift
//  millioTests
//
//  Created by Codex on 04.04.2026.
//

import Testing
import CoreGraphics
@testable import millio

struct DashboardWidgetLayoutPlannerTests {
    @Test("Быстрые действия и пары собираются в один ряд")
    func pairsCompactWidgetsIntoSingleRow() {
        let rows = DashboardWidgetLayoutPlanner.rows(for: [
            .finances,
            .quickActions,
            .converter,
            .services
        ], availableWidth: CGFloat(900))

        #expect(rows == [
            [.finances],
            [.quickActions, .converter],
            [.services]
        ])
    }

    @Test("На узком экране компактные виджеты не пытаются встать в один ряд")
    func keepsCompactWidgetsStackedOnNarrowWidth() {
        let rows = DashboardWidgetLayoutPlanner.rows(for: [
            .quickActions,
            .converter,
            .services
        ], availableWidth: CGFloat(360))

        #expect(rows == [
            [.quickActions],
            [.converter],
            [.services]
        ])
    }

    @Test("Если один из компактных виджетов скрыт, второй остается отдельным блоком")
    func keepsSingleCompactWidgetVisible() {
        let rows = DashboardWidgetLayoutPlanner.rows(for: [
            .converter,
            .finances
        ], availableWidth: CGFloat(900))

        #expect(rows == [
            [.converter],
            [.finances]
        ])
    }
}
