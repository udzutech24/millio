//
//  CashbackImportCategoryResolver.swift
//  millio
//
//  Created by Codex on 26.02.2026.
//

import Foundation

/// Резолвер импортированных названий категорий в системные категории Millio.
/// Работает консервативно: маппит только очевидные совпадения.
struct CashbackImportCategoryResolver {
    private struct Rule {
        let category: CashbackCategory
        let keywords: [String]
    }

    /// Stable aliases for exact matches from import sources.
    /// Do not rely only on localized displayName: test/device locale may differ.
    private static let exactAliases: [String: CashbackCategory] = {
        var map: [String: CashbackCategory] = [:]

        for category in CashbackCategory.allCases {
            map[normalize(category.rawValue)] = category
        }

        map[normalize("Авиабилеты")] = .airlines
        map[normalize("Красота")] = .beauty
        map[normalize("Супермаркеты")] = .supermarket
        map[normalize("Рестораны")] = .restaurant
        map[normalize("Аптеки")] = .pharmacy
        map[normalize("Транспорт")] = .transport
        map[normalize("Развлечения")] = .entertainment
        map[normalize("Онлайн")] = .online

        return map
    }()

    private let rules: [Rule] = [
        Rule(category: .airlines, keywords: ["авиабил", "авиа", "перелет"]),
        Rule(category: .gasStation, keywords: ["азс", "заправ", "топлив"]),
        Rule(category: .supermarket, keywords: ["супермаркет", "продукт"]),
        Rule(category: .restaurant, keywords: ["ресторан", "еда", "общепит"]),
        Rule(category: .beauty, keywords: ["красот", "космет", "beauty"]),
        Rule(category: .pharmacy, keywords: ["аптек"]),
        Rule(category: .transport, keywords: ["транспорт", "каршеринг"]),
        Rule(category: .entertainment, keywords: ["развлеч", "кино", "театр"]),
        Rule(category: .online, keywords: ["онлайн", "интернет", "маркетплейс"])
    ]

    func resolveSystemCategoryRaw(for importedName: String) -> String? {
        let normalizedImported = Self.normalize(importedName)
        guard !normalizedImported.isEmpty else { return nil }

        if let exact = Self.exactAliases[normalizedImported] {
            return exact.rawValue
        }

        for rule in rules {
            if rule.keywords.contains(where: { normalizedImported.contains($0) }) {
                return rule.category.rawValue
            }
        }

        return nil
    }

    private static func normalize(_ value: String) -> String {
        let lowered = value.lowercased()
        let lettersAndDigits = lowered.replacingOccurrences(
            of: #"[^a-zа-я0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        return lettersAndDigits
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
