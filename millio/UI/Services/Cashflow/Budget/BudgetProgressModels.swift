//
//  BudgetProgressModels.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

enum BudgetStatus: Equatable {
    case normal
    case warning
    case critical
    case exceeded
}

struct BudgetCategoryProgressSnapshot: Equatable, Identifiable {
    let id: String
    let categoryRawValue: String
    let title: String
    let spent: Double
    let limit: Double
    let remaining: Double
    let progress: Double
    let status: BudgetStatus
}

struct BudgetProgressSnapshot: Equatable {
    let spent: Double
    let limit: Double
    let remaining: Double
    let progress: Double
    let status: BudgetStatus
    let categorySnapshots: [BudgetCategoryProgressSnapshot]
    let categoriesLimitOverflow: Double
}
