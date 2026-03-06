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
        map[normalize("Airlines")] = .airlines
        map[normalize("Flights")] = .airlines
        map[normalize("Air tickets")] = .airlines
        map[normalize("Airfare")] = .airlines
        map[normalize("Красота")] = .beauty
        map[normalize("Beauty")] = .beauty
        map[normalize("Супермаркеты")] = .supermarket
        map[normalize("Supermarkets")] = .supermarket
        map[normalize("Groceries")] = .supermarket
        map[normalize("Рестораны")] = .restaurant
        map[normalize("Restaurants")] = .restaurant
        map[normalize("Dining")] = .restaurant
        map[normalize("Аптеки")] = .pharmacy
        map[normalize("Pharmacies")] = .pharmacy
        map[normalize("Drugstores")] = .pharmacy
        map[normalize("Транспорт")] = .transport
        map[normalize("Transport")] = .transport
        map[normalize("Развлечения")] = .entertainment
        map[normalize("Entertainment")] = .entertainment
        map[normalize("Онлайн")] = .online
        map[normalize("Online")] = .online
        map[normalize("Hotels")] = .hotels
        map[normalize("Marketplaces")] = .marketplaces
        map[normalize("Electronics")] = .electronics
        map[normalize("Telecom")] = .telecom
        map[normalize("Internet")] = .internet

        return map
    }()

    private let rules: [Rule] = [
        Rule(category: .airlines, keywords: ["авиабил", "авиа", "перелет", "airline", "flight", "air ticket", "airfare"]),
        Rule(category: .gasStation, keywords: ["азс", "заправ", "топлив", "fuel", "gas station", "petrol"]),
        Rule(category: .supermarket, keywords: ["супермаркет", "продукт", "supermarket", "grocery"]),
        Rule(category: .restaurant, keywords: ["ресторан", "еда", "общепит", "restaurant", "dining"]),
        Rule(category: .beauty, keywords: ["красот", "космет", "beauty"]),
        Rule(category: .pharmacy, keywords: ["аптек", "pharmac", "drugstore"]),
        Rule(category: .transport, keywords: ["транспорт", "каршеринг", "transport", "public transit"]),
        Rule(category: .entertainment, keywords: ["развлеч", "кино", "театр", "entertainment", "movie", "cinema"]),
        Rule(category: .online, keywords: ["онлайн", "интернет", "маркетплейс", "online", "internet"]),
        Rule(category: .hotels, keywords: ["отел", "гостиниц", "hotel"]),
        Rule(category: .marketplaces, keywords: ["маркетплейс", "marketplace"]),
        Rule(category: .electronics, keywords: ["техник", "электрон", "electronic", "gadget"]),
        Rule(category: .telecom, keywords: ["связ", "mobile", "telecom", "cellular"])
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
