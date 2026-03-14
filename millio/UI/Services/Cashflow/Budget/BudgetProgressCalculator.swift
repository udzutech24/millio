//
//  BudgetProgressCalculator.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

enum BudgetProgressCalculator {
    static let warningThreshold: Double = 0.7
    static let criticalThreshold: Double = 0.9

    static func calculate(
        totalSpent: Double,
        totalLimit: Double,
        categorySpentByRawValue: [String: Double] = [:],
        categoryLimits: [BudgetCategoryLimit] = [],
        categoryTitleResolver: (String) -> String = { $0 }
    ) -> BudgetProgressSnapshot? {
        let normalizedLimit = max(0, totalLimit)
        guard normalizedLimit > 0.0000001 else { return nil }

        let normalizedSpent = max(0, totalSpent)
        let remaining = normalizedLimit - normalizedSpent
        let progress = normalizedSpent / normalizedLimit
        let categorySnapshots = categoryLimits
            .filter { $0.limitAmount > 0.0000001 }
            .map { limit in
                let spent = max(0, categorySpentByRawValue[limit.categoryRawValue, default: 0])
                let categoryRemaining = limit.limitAmount - spent
                let categoryProgress = spent / max(limit.limitAmount, 0.0000001)
                return BudgetCategoryProgressSnapshot(
                    id: limit.categoryLimitID,
                    categoryRawValue: limit.categoryRawValue,
                    title: categoryTitleResolver(limit.categoryRawValue),
                    spent: spent,
                    limit: limit.limitAmount,
                    remaining: categoryRemaining,
                    progress: categoryProgress,
                    status: status(for: categoryProgress)
                )
            }
            .sorted {
                if $0.status != $1.status {
                    return severity(for: $0.status) > severity(for: $1.status)
                }
                return $0.spent > $1.spent
            }
        let categoriesLimitTotal = categoryLimits.reduce(0) { $0 + max(0, $1.limitAmount) }

        return BudgetProgressSnapshot(
            spent: normalizedSpent,
            limit: normalizedLimit,
            remaining: remaining,
            progress: progress,
            status: status(for: progress),
            categorySnapshots: categorySnapshots,
            categoriesLimitOverflow: max(0, categoriesLimitTotal - normalizedLimit)
        )
    }

    static func status(for progress: Double) -> BudgetStatus {
        let normalized = max(progress, 0)
        if normalized > 1.0 {
            return .exceeded
        }
        if normalized >= criticalThreshold {
            return .critical
        }
        if normalized >= warningThreshold {
            return .warning
        }
        return .normal
    }

    private static func severity(for status: BudgetStatus) -> Int {
        switch status {
        case .normal:
            return 0
        case .warning:
            return 1
        case .critical:
            return 2
        case .exceeded:
            return 3
        }
    }
}
