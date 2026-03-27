//
//  CashflowBulkExpenseMerchantCategoryPrefs.swift
//  millio
//
//  Created by Codex on 20.03.2026.
//

import Foundation

struct CashflowBulkExpenseMerchantCategoryPrefs {
    private let defaults: UserDefaults
    private let storageKey = "cashflow.bulk_expense.merchant_category_map.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func categoryRaw(for merchantTitle: String) -> String? {
        let key = Self.normalizeMerchantTitle(merchantTitle)
        guard !key.isEmpty else { return nil }
        return mappings()[key]
    }

    func remember(categoryRaw: String, for merchantTitle: String) {
        let key = Self.normalizeMerchantTitle(merchantTitle)
        guard !key.isEmpty else { return }

        var values = mappings()
        values[key] = categoryRaw
        defaults.set(values, forKey: storageKey)
    }

    func remapCategory(from sourceRaw: String, to targetRaw: String) {
        guard sourceRaw != targetRaw else { return }

        var values = mappings()
        var didChange = false

        for (key, value) in values where value == sourceRaw {
            values[key] = targetRaw
            didChange = true
        }

        if didChange {
            defaults.set(values, forKey: storageKey)
        }
    }

    func mappingsSnapshot() -> [String: String] {
        mappings()
    }

    func replaceMappings(_ values: [String: String]) {
        defaults.set(values, forKey: storageKey)
    }

    private func mappings() -> [String: String] {
        defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    static func normalizeMerchantTitle(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
