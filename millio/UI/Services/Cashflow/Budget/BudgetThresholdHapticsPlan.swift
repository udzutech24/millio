//
//  BudgetThresholdHapticsPlan.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

enum BudgetThresholdHapticsPlan {
    static let thresholds: [Double] = [
        BudgetProgressCalculator.warningThreshold,
        BudgetProgressCalculator.criticalThreshold,
        1.0
    ]

    static func step(for progress: Double) -> Int {
        let normalized = max(progress, 0)
        return thresholds.lastIndex(where: { normalized >= $0 }) ?? -1
    }
}
