//
//  FinanceDynamicsPresentation.swift
//  millio
//
//  Presentation helpers for the finance dynamics screen.
//  Keeps net-total math consistent between the chart/header and the breakdown table.
//

import Foundation

enum FinanceDynamicsPresentation {
    static func totalRow(
        from breakdown: [DynamicsBreakdownItem],
        viewMode: DynamicsViewMode
    ) -> DynamicsBreakdownItem? {
        guard !breakdown.isEmpty else { return nil }

        let startSum = breakdown.reduce(0) { partial, item in
            partial + signedValue(item.startValue, for: item, viewMode: viewMode)
        }
        let endSum = breakdown.reduce(0) { partial, item in
            partial + signedValue(item.endValue, for: item, viewMode: viewMode)
        }
        let delta = endSum - startSum
        let percent: Double = abs(startSum) > 0.01 ? (delta / abs(startSum)) * 100 : 0

        return DynamicsBreakdownItem(
            id: "total",
            name: L("finances.dynamics.chart.total_label"),
            startValue: startSum,
            endValue: endSum,
            delta: delta,
            deltaPercent: percent,
            icon: nil,
            accountType: nil,
            isCreditCard: false,
            isArchived: false
        )
    }

    private static func signedValue(
        _ value: Double,
        for item: DynamicsBreakdownItem,
        viewMode: DynamicsViewMode
    ) -> Double {
        guard viewMode == .accounts else { return value }
        let isLiability = item.accountType == .credit || item.isCreditCard
        return isLiability ? -abs(value) : value
    }
}
