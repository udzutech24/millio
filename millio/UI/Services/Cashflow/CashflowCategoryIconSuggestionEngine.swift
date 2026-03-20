//
//  CashflowCategoryIconSuggestionEngine.swift
//  millio
//
//  Created by Codex on 20.03.2026.
//

import Foundation

enum CashflowCategoryIconSuggestionEngine {
    static func suggestedIcons(forExpenseName name: String) -> [String] {
        ExpenseCategoryCatalog.suggestedIcons(for: name)
    }
}
