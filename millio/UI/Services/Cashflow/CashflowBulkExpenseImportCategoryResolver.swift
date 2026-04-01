//
//  CashflowBulkExpenseImportCategoryResolver.swift
//  millio
//
//  Created by Codex on 11.03.2026.
//

import Foundation

struct CashflowBulkExpenseImportCategoryResolver {
    private static let normalizationLocale = Locale(identifier: "en_US_POSIX")

    func resolve(
        title: String,
        availableOptions: [CashflowCategoryOption],
        preferredRawValue: String? = nil
    ) -> CashflowBulkExpenseCategoryResolution {
        let normalizedTitle = normalize(title)
        let fallback = availableOptions.first { $0.rawValue == ExpenseCategory.other.rawValue }
            ?? CashflowCategoryOption(
                rawValue: ExpenseCategory.other.rawValue,
                displayName: ExpenseCategory.other.displayName,
                icon: ExpenseCategory.other.icon,
                isCustom: false
            )

        guard !normalizedTitle.isEmpty else {
            return CashflowBulkExpenseCategoryResolution(option: fallback, confidence: .low)
        }

        if let preferredRawValue,
           let preferredOption = availableOptions.first(where: { $0.rawValue == preferredRawValue }) {
            return CashflowBulkExpenseCategoryResolution(option: preferredOption, confidence: .high)
        }

        var bestOption = fallback
        var bestScore: Double = 0.0

        for option in availableOptions {
            let score = score(option: option, normalizedTitle: normalizedTitle)
            if score > bestScore {
                bestScore = score
                bestOption = option
            }
        }

        let confidence: CashflowBulkExpenseImportMatchConfidence
        switch bestScore {
        case 0.86...:
            confidence = .high
        case 0.62...:
            confidence = .medium
        default:
            confidence = .low
        }

        return CashflowBulkExpenseCategoryResolution(option: bestOption, confidence: confidence)
    }

    func suggestedOptions(
        title: String,
        availableOptions: [CashflowCategoryOption],
        preferredRawValue: String? = nil,
        limit: Int = 3
    ) -> [CashflowCategoryOption] {
        let normalizedTitle = normalize(title)
        var ranked: [(option: CashflowCategoryOption, score: Double)] = []

        if let preferredRawValue,
           let preferredOption = availableOptions.first(where: { $0.rawValue == preferredRawValue }) {
            ranked.append((preferredOption, 2.0))
        }

        for option in availableOptions where option.rawValue != ExpenseCategory.other.rawValue {
            let score = score(option: option, normalizedTitle: normalizedTitle)
            guard score > 0 else { continue }
            ranked.append((option, score))
        }

        var seen = Set<String>()
        return ranked
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.0000001 {
                    return lhs.score > rhs.score
                }
                return lhs.option.displayName < rhs.option.displayName
            }
            .compactMap { item in
                guard seen.insert(item.option.rawValue).inserted else { return nil }
                return item.option
            }
            .prefix(limit)
            .map(\.self)
    }

    private func score(option: CashflowCategoryOption, normalizedTitle: String) -> Double {
        let normalizedName = normalize(option.displayName)
        if normalizedTitle == normalizedName || normalizedTitle == option.rawValue {
            return 1.0
        }
        if normalizedTitle.contains(normalizedName) || normalizedName.contains(normalizedTitle) {
            return option.isCustom ? 0.9 : 0.82
        }

        var score = keywordScore(for: option.rawValue, title: normalizedTitle)
        if normalizedName.split(separator: " ").count > 1 {
            let allWordsMatch = normalizedName
                .split(separator: " ")
                .allSatisfy { normalizedTitle.contains(String($0)) }
            if allWordsMatch {
                score = max(score, 0.78)
            }
        }
        return score
    }

    private func keywordScore(for rawValue: String, title: String) -> Double {
        let keywords = Self.keywordsByCategory[rawValue] ?? []
        var score: Double = 0

        for keyword in keywords {
            if title == keyword {
                score = max(score, 0.96)
            } else if title.contains(keyword) {
                score = max(score, keyword.count >= 6 ? 0.9 : 0.74)
            }
        }

        return score
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Self.normalizationLocale)
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let keywordsByCategory: [String: [String]] = Dictionary(
        uniqueKeysWithValues: ExpenseCategory.allCases.map { category in
            let metadata = ExpenseCategoryCatalog.metadata(for: category)
            let normalizedKeywords = Set(
                ([metadata.displayNameRU, metadata.displayNameEN] + metadata.aliases)
                    .map(Self.normalizeKeyword)
                    .filter { !$0.isEmpty }
            )
            return (category.rawValue, Array(normalizedKeywords))
        }
    )

    private static func normalizeKeyword(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: normalizationLocale)
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
