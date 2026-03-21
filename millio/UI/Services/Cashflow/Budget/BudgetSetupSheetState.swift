//
//  BudgetSetupSheetState.swift
//  millio
//
//  Created by Codex on 21.03.2026.
//

import Foundation

struct BudgetSetupSheetState: Equatable {
    let isTotalLimitEnabled: Bool
    let parsedTotal: Double
    let categoryLimits: [String: Double]
    let hasExistingAmount: Bool
    let hasExistingCategoryLimits: Bool

    var categoryLimitSum: Double {
        categoryLimits.values.reduce(0, +)
    }

    var hasOverflowConflict: Bool {
        isTotalLimitEnabled && parsedTotal > 0 && categoryLimitSum - parsedTotal > 0.0000001
    }

    var effectiveTotalAmount: Double {
        isTotalLimitEnabled ? parsedTotal : 0
    }

    var canSave: Bool {
        if isTotalLimitEnabled {
            return parsedTotal > 0 && !hasOverflowConflict
        }
        return !categoryLimits.isEmpty || hasExistingConfiguration
    }

    var hasExistingConfiguration: Bool {
        hasExistingAmount || hasExistingCategoryLimits
    }

    static func isTotalLimitInitiallyEnabled(_ initialTotalAmount: Double?) -> Bool {
        guard let initialTotalAmount else { return false }
        return initialTotalAmount > 0.0000001
    }
}
