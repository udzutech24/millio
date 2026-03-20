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

        map[normalize("Все покупки")] = .allPurchases
        map[normalize("На все покупки")] = .allPurchases
        map[normalize("All purchases")] = .allPurchases
        map[normalize("Base cashback")] = .allPurchases
        map[normalize("Авиабилеты")] = .airlines
        map[normalize("Airlines")] = .airlines
        map[normalize("Flights")] = .airlines
        map[normalize("Air tickets")] = .airlines
        map[normalize("Airfare")] = .airlines
        map[normalize("Красота")] = .beauty
        map[normalize("Beauty")] = .beauty
        map[normalize("Продукты")] = .supermarket
        map[normalize("Супермаркеты")] = .supermarket
        map[normalize("Supermarkets")] = .supermarket
        map[normalize("Groceries")] = .supermarket
        map[normalize("Рестораны")] = .restaurant
        map[normalize("Restaurants")] = .restaurant
        map[normalize("Dining")] = .restaurant
        map[normalize("Аптеки")] = .pharmacy
        map[normalize("Pharmacies")] = .pharmacy
        map[normalize("Drugstores")] = .pharmacy
        map[normalize("Медицинские клиники")] = .healthcare
        map[normalize("Medical clinics")] = .healthcare
        map[normalize("Healthcare")] = .healthcare
        map[normalize("Транспорт")] = .transport
        map[normalize("Transport")] = .transport
        map[normalize("Такси")] = .taxi
        map[normalize("Яндекс Такси")] = .taxi
        map[normalize("Комфорт")] = .taxi
        map[normalize("Комфорт+")] = .taxi
        map[normalize("Ultima")] = .taxi
        map[normalize("Taxi")] = .taxi
        map[normalize("Развлечения")] = .entertainment
        map[normalize("Entertainment")] = .entertainment
        map[normalize("Онлайн")] = .online
        map[normalize("Online")] = .online
        map[normalize("Hotels")] = .hotels
        map[normalize("Marketplaces")] = .marketplaces
        map[normalize("Electronics")] = .electronics
        map[normalize("Дом и ремонт")] = .homeRepair
        map[normalize("Home repair")] = .homeRepair
        map[normalize("Детские товары")] = .kids
        map[normalize("Kids goods")] = .kids
        map[normalize("Яндекс Лавка")] = .supermarket
        map[normalize("Лавка")] = .supermarket
        map[normalize("Цветы")] = .flowersGifts
        map[normalize("Цветы и подарки")] = .flowersGifts
        map[normalize("Telecom")] = .telecom
        map[normalize("Internet")] = .internet

        return map
    }()

    private let rules: [Rule] = [
        Rule(category: .allPurchases, keywords: ["все покупки", "на все покупки", "all purchases", "base cashback"]),
        Rule(category: .airlines, keywords: ["авиабил", "авиа", "перелет", "airline", "flight", "air ticket", "airfare"]),
        Rule(category: .gasStation, keywords: ["азс", "заправ", "топлив", "fuel", "gas station", "petrol"]),
        Rule(category: .supermarket, keywords: ["супермаркет", "продукт", "supermarket", "grocery"]),
        Rule(category: .restaurant, keywords: ["ресторан", "еда", "общепит", "restaurant", "dining"]),
        Rule(category: .beauty, keywords: ["красот", "космет", "beauty"]),
        Rule(category: .pharmacy, keywords: ["аптек", "pharmac", "drugstore"]),
        Rule(category: .healthcare, keywords: ["медицин", "клиник", "healthcare", "medical clinic"]),
        Rule(category: .transport, keywords: ["транспорт", "каршеринг", "transport", "public transit"]),
        Rule(category: .taxi, keywords: ["такси", "taxi", "комфорт", "ultima"]),
        Rule(category: .entertainment, keywords: ["развлеч", "кино", "театр", "entertainment", "movie", "cinema"]),
        Rule(category: .online, keywords: ["онлайн", "интернет", "маркетплейс", "online", "internet"]),
        Rule(category: .hotels, keywords: ["отел", "гостиниц", "hotel"]),
        Rule(category: .marketplaces, keywords: ["маркетплейс", "marketplace"]),
        Rule(category: .electronics, keywords: ["техник", "электрон", "electronic", "gadget"]),
        Rule(category: .homeRepair, keywords: ["дом и ремонт", "ремонт", "home repair"]),
        Rule(category: .kids, keywords: ["детск", "kids"]),
        Rule(category: .telecom, keywords: ["связ", "mobile", "telecom", "cellular"]),
        Rule(category: .supermarket, keywords: ["лавка", "супермаркет", "продукт", "supermarket", "grocery"]),
        Rule(category: .flowersGifts, keywords: ["цвет", "подар", "flowers", "gift"])
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

    /// Import flow must stay conservative: bank tariff labels should remain custom categories,
    /// otherwise we silently destroy user intent during screenshot/manual import.
    func resolveSystemCategoryRawForImport(_ importedName: String) -> String? {
        let normalizedImported = Self.normalize(importedName)
        guard !normalizedImported.isEmpty else { return nil }

        switch normalizedImported {
        case Self.normalize("Комфорт"),
             Self.normalize("Комфорт+"),
             Self.normalize("Ultima"):
            return nil
        default:
            break
        }

        return resolveSystemCategoryRaw(for: importedName)
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
