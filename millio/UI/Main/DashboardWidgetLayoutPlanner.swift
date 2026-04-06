//
//  DashboardWidgetLayoutPlanner.swift
//  millio
//
//  Created by Codex on 04.04.2026.
//

import CoreGraphics
import Foundation

struct DashboardWidgetLayoutPlanner {
    static let compactPairMinimumWidth: CGFloat = 700

    static func rows(
        for kinds: [DashboardWidgetKind],
        availableWidth: CGFloat = .greatestFiniteMagnitude
    ) -> [[DashboardWidgetKind]] {
        let shouldPairCompactWidgets = Set(kinds).isSuperset(of: [.quickActions, .converter])
            && availableWidth >= compactPairMinimumWidth
        var rows: [[DashboardWidgetKind]] = []
        var didAppendCompactPair = false

        for kind in kinds {
            if shouldPairCompactWidgets, kind == .quickActions || kind == .converter {
                guard !didAppendCompactPair else { continue }
                rows.append([.quickActions, .converter])
                didAppendCompactPair = true
            } else {
                rows.append([kind])
            }
        }

        return rows
    }
}
