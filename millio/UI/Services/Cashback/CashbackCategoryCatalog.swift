//
//  CashbackCategoryCatalog.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

struct CashbackCategoryMetadata: Equatable {
    let category: CashbackCategory
    let displayNameRU: String
    let displayNameEN: String
    let icon: String
    let aliases: [String]

    func localizedDisplayName(locale: Locale = .autoupdatingCurrent) -> String {
        let languageCode = locale.identifier
            .split(separator: "_")
            .first
            .map { String($0).lowercased() } ?? "en"
        return languageCode == "ru" ? displayNameRU : displayNameEN
    }
}

enum CashbackCategoryCatalog {
    static let allMetadata: [CashbackCategoryMetadata] = [
        .init(category: .allPurchases, displayNameRU: "Все покупки", displayNameEN: "All purchases", icon: "🛒", aliases: ["все покупки", "all purchases", "base cashback"]),
        .init(category: .gasStation, displayNameRU: "АЗС", displayNameEN: "Fuel", icon: "⛽️", aliases: ["топливо", "азс", "заправки", "fuel", "gas station", "petrol"]),
        .init(category: .supermarket, displayNameRU: "Продукты", displayNameEN: "Groceries", icon: "🛒", aliases: ["продукты", "супермаркеты", "groceries", "grocery", "supermarket", "вкусвилл", "пятерочка"]),
        .init(category: .restaurant, displayNameRU: "Кафе", displayNameEN: "Cafes", icon: "☕️", aliases: ["кафе", "рестораны", "restaurants", "restaurant", "dining"]),
        .init(category: .fastFood, displayNameRU: "Фастфуд", displayNameEN: "Fast food", icon: "🍔", aliases: ["фастфуд", "fast food", "burger", "pizza"]),
        .init(category: .coffeeShop, displayNameRU: "Кофейни", displayNameEN: "Coffee shops", icon: "☕️", aliases: ["кофейня", "кофе", "coffee", "coffee shop"]),
        .init(category: .pharmacy, displayNameRU: "Аптеки", displayNameEN: "Pharmacies", icon: "💊", aliases: ["аптека", "аптеки", "pharmacy", "drugstore"]),
        .init(category: .healthcare, displayNameRU: "Медицина", displayNameEN: "Medical", icon: "🩺", aliases: ["медицина", "клиника", "врач", "medical", "healthcare", "dental"]),
        .init(category: .transport, displayNameRU: "Транспорт", displayNameEN: "Transport", icon: "🚇", aliases: ["транспорт", "metro", "public transport", "bus", "transit"]),
        .init(category: .taxi, displayNameRU: "Такси", displayNameEN: "Taxi", icon: "🚕", aliases: ["такси", "taxi", "uber", "yandex go", "rideshare"]),
        .init(category: .carSharing, displayNameRU: "Каршеринг", displayNameEN: "Car sharing", icon: "🚗", aliases: ["каршеринг", "car sharing", "carsharing"]),
        .init(category: .autoServices, displayNameRU: "Сервис", displayNameEN: "Service", icon: "🛠️", aliases: ["автосервис", "сто", "car service", "auto repair", "maintenance"]),
        .init(category: .entertainment, displayNameRU: "Развлечения", displayNameEN: "Entertainment", icon: "🎮", aliases: ["развлечения", "entertainment", "cinema", "movie", "theatre"]),
        .init(category: .cinema, displayNameRU: "Кино", displayNameEN: "Cinema", icon: "🎬", aliases: ["кино", "cinema", "movie"]),
        .init(category: .travel, displayNameRU: "Путешествия", displayNameEN: "Travel", icon: "✈️", aliases: ["путешествия", "travel", "trip"]),
        .init(category: .hotels, displayNameRU: "Отели", displayNameEN: "Hotels", icon: "🏨", aliases: ["отели", "hotel", "hotels", "lodging"]),
        .init(category: .airlines, displayNameRU: "Авиабилеты", displayNameEN: "Flights", icon: "✈️", aliases: ["авиабилеты", "flights", "airline", "airfare"]),
        .init(category: .railway, displayNameRU: "Поезда", displayNameEN: "Rail", icon: "🚆", aliases: ["поезда", "railway", "train tickets", "rail"]),
        .init(category: .online, displayNameRU: "Онлайн", displayNameEN: "Online", icon: "🌐", aliases: ["онлайн", "online", "internet", "ecommerce"]),
        .init(category: .marketplaces, displayNameRU: "Маркетплейсы", displayNameEN: "Marketplaces", icon: "📦", aliases: ["маркетплейсы", "marketplace", "ozon", "wb", "wildberries", "amazon"]),
        .init(category: .electronics, displayNameRU: "Техника", displayNameEN: "Electronics", icon: "💻", aliases: ["техника", "electronics", "gadgets", "electronic"]),
        .init(category: .homeGoods, displayNameRU: "Дом", displayNameEN: "Home", icon: "🏠", aliases: ["дом", "home goods", "товары для дома", "household"]),
        .init(category: .furniture, displayNameRU: "Мебель", displayNameEN: "Furniture", icon: "🛋️", aliases: ["мебель", "furniture"]),
        .init(category: .clothing, displayNameRU: "Одежда", displayNameEN: "Clothing", icon: "👕", aliases: ["одежда", "clothing", "fashion", "apparel"]),
        .init(category: .shoes, displayNameRU: "Обувь", displayNameEN: "Shoes", icon: "👟", aliases: ["обувь", "shoes", "footwear"]),
        .init(category: .beauty, displayNameRU: "Красота", displayNameEN: "Beauty", icon: "💄", aliases: ["красота", "beauty", "cosmetics", "spa", "barber"]),
        .init(category: .sport, displayNameRU: "Спорт", displayNameEN: "Sport", icon: "🏋️", aliases: ["спорт", "gym", "fitness", "sport"]),
        .init(category: .books, displayNameRU: "Книги", displayNameEN: "Books", icon: "📚", aliases: ["книги", "books", "bookstore"]),
        .init(category: .education, displayNameRU: "Образование", displayNameEN: "Education", icon: "🎓", aliases: ["образование", "education", "courses", "tuition"]),
        .init(category: .kids, displayNameRU: "Дети", displayNameEN: "Kids", icon: "🧸", aliases: ["дети", "kids", "baby", "toys"]),
        .init(category: .pets, displayNameRU: "Питомцы", displayNameEN: "Pets", icon: "🐾", aliases: ["питомцы", "pets", "pet store", "veterinary"]),
        .init(category: .telecom, displayNameRU: "Связь", displayNameEN: "Telecom", icon: "📱", aliases: ["связь", "telecom", "mobile", "cellular"]),
        .init(category: .internet, displayNameRU: "Интернет", displayNameEN: "Internet", icon: "📶", aliases: ["интернет", "internet", "wifi", "isp"]),
        .init(category: .utilities, displayNameRU: "ЖКХ", displayNameEN: "Utilities", icon: "💡", aliases: ["жкх", "коммунальные", "utilities", "electricity", "water"]),
        .init(category: .digitalServices, displayNameRU: "Сервисы", displayNameEN: "Digital", icon: "🖥️", aliases: ["сервисы", "digital services", "software", "apps", "saas"]),
        .init(category: .subscriptions, displayNameRU: "Подписки", displayNameEN: "Subscriptions", icon: "🔁", aliases: ["подписки", "subscription", "subscriptions", "netflix", "spotify"]),
        .init(category: .insurance, displayNameRU: "Страхование", displayNameEN: "Insurance", icon: "🛡️", aliases: ["страхование", "insurance"]),
        .init(category: .homeRepair, displayNameRU: "Ремонт", displayNameEN: "Repair", icon: "🔧", aliases: ["ремонт", "diy", "home repair", "hardware"]),
        .init(category: .flowersGifts, displayNameRU: "Подарки", displayNameEN: "Gifts", icon: "🎁", aliases: ["подарки", "цветы", "gift", "flowers"]),
        .init(category: .alcohol, displayNameRU: "Алкоголь", displayNameEN: "Alcohol", icon: "🍷", aliases: ["алкоголь", "alcohol", "wine", "beer"]),
        .init(category: .other, displayNameRU: "Разное", displayNameEN: "Other", icon: "🧩", aliases: ["разное", "прочее", "other", "misc", "unknown"])
    ]

    private static let metadataByCategory = Dictionary(uniqueKeysWithValues: allMetadata.map { ($0.category, $0) })
    private static let metadataByRawValue = Dictionary(uniqueKeysWithValues: allMetadata.map { ($0.category.rawValue, $0) })

    static func metadata(for category: CashbackCategory) -> CashbackCategoryMetadata {
        metadataByCategory[category] ?? fallbackMetadata
    }

    static func metadata(forRawValue rawValue: String) -> CashbackCategoryMetadata? {
        metadataByRawValue[rawValue]
    }

    static func matchesSearch(rawValue: String, query: String, locale: Locale = .autoupdatingCurrent) -> Bool {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return true }
        guard let metadata = metadata(forRawValue: rawValue) else { return false }

        let candidates = [metadata.localizedDisplayName(locale: locale), metadata.displayNameRU, metadata.displayNameEN, rawValue] + metadata.aliases
        return candidates.map(normalize).contains { candidate in
            candidate.contains(normalizedQuery) || normalizedQuery.contains(candidate)
        }
    }

    private static let fallbackMetadata = CashbackCategoryMetadata(
        category: .other,
        displayNameRU: "Разное",
        displayNameEN: "Other",
        icon: "🧩",
        aliases: ["разное", "прочее", "other"]
    )

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
