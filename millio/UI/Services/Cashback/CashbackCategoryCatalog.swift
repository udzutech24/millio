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

    func localizedDisplayName(locale: Locale? = nil) -> String {
        let languageCode: String
        if let locale {
            languageCode = locale.identifier
                .split(separator: "_")
                .first
                .map { String($0).lowercased() } ?? "en"
        } else {
            switch LanguageManager.shared.currentLanguage {
            case .russian:
                languageCode = "ru"
            case .english:
                languageCode = "en"
            case .system:
                languageCode = AppLocalization.currentAppLocale.identifier
                    .split(separator: "_")
                    .first
                    .map { String($0).lowercased() } ?? "en"
            }
        }
        return languageCode == "ru" ? displayNameRU : displayNameEN
    }
}

enum CashbackCategoryCatalog {
    static let allMetadata: [CashbackCategoryMetadata] = [
        .init(category: .allPurchases, displayNameRU: "Все покупки", displayNameEN: "All purchases", icon: "🛒", aliases: ["все покупки", "all purchases", "base cashback"]),
        .init(category: .gasStation, displayNameRU: "АЗС", displayNameEN: "Gas stations", icon: "⛽️", aliases: ["топливо", "азс", "заправки", "fuel", "gas station", "gas stations", "petrol"]),
        .init(category: .supermarket, displayNameRU: "Продукты", displayNameEN: "Groceries", icon: "🛒", aliases: ["продукты", "супермаркеты", "groceries", "grocery", "supermarket", "supermarkets", "вкусвилл", "пятерочка"]),
        .init(category: .restaurant, displayNameRU: "Кафе", displayNameEN: "Restaurants", icon: "🍽️", aliases: ["кафе", "рестораны", "restaurants", "restaurant", "dining"]),
        .init(category: .fastFood, displayNameRU: "Фастфуд", displayNameEN: "Fast food", icon: "🍔", aliases: ["фастфуд", "быстрая еда", "fast food", "burger", "pizza", "пицца", "пиццерия", "роллы", "суши", "бургер", "шаверма", "шаурма", "доставка еды"]),
        .init(category: .coffeeShop, displayNameRU: "Кофейни", displayNameEN: "Coffee shops", icon: "☕️", aliases: ["кофейня", "кофе", "coffee", "coffee shop"]),
        .init(category: .pharmacy, displayNameRU: "Аптеки", displayNameEN: "Pharmacies", icon: "💊", aliases: ["аптека", "аптеки", "pharmacy", "drugstore"]),
        .init(category: .healthcare, displayNameRU: "Медицина", displayNameEN: "Medical", icon: "🩺", aliases: ["медицина", "медицинские услуги", "клиника", "врач", "medical", "medical services", "healthcare", "dental"]),
        .init(category: .transport, displayNameRU: "Транспорт", displayNameEN: "Transport", icon: "🚕", aliases: ["транспорт", "metro", "public transport", "bus", "transit"]),
        .init(category: .taxi, displayNameRU: "Такси", displayNameEN: "Taxi", icon: "🚖", aliases: ["такси", "taxi", "uber", "yandex go", "rideshare"]),
        .init(category: .carSharing, displayNameRU: "Каршеринг", displayNameEN: "Car sharing", icon: "🚗", aliases: ["каршеринг", "car sharing", "carsharing"]),
        .init(category: .autoServices, displayNameRU: "Авто", displayNameEN: "Auto", icon: "🛠️", aliases: ["авто", "автосервис", "сто", "car service", "auto repair", "maintenance"]),
        .init(category: .entertainment, displayNameRU: "Развлечения", displayNameEN: "Entertainment", icon: "🎮", aliases: ["развлечения", "entertainment", "cinema", "movie", "theatre"]),
        .init(category: .cinema, displayNameRU: "Кино", displayNameEN: "Cinema", icon: "🎬", aliases: ["кино", "cinema", "movie"]),
        .init(category: .travel, displayNameRU: "Путешествия", displayNameEN: "Travel", icon: "🧳", aliases: ["путешествия", "travel", "trip"]),
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

    static func suggestedIcons(for name: String) -> [String] {
        let normalized = normalize(name)
        guard !normalized.isEmpty else {
            return Array(defaultSuggestedIcons.prefix(8))
        }

        let matchedMetadata = rankedMetadata(for: normalized)
        let semanticIcons = matchedMetadata
            .prefix(3)
            .flatMap { semanticIconsByCategory[$0.category] ?? [] }
        let icon = matchedMetadata.first?.icon
        var combined: [String] = []
        if let icon {
            combined.append(icon)
        }
        combined.append(contentsOf: semanticIcons)
        combined.append(contentsOf: heuristicIcons(for: normalized))
        combined.append(contentsOf: defaultSuggestedIcons)

        var unique: [String] = []
        for item in combined where !unique.contains(item) {
            unique.append(item)
        }
        return Array(unique.prefix(10))
    }

    private static let fallbackMetadata = CashbackCategoryMetadata(
        category: .other,
        displayNameRU: "Разное",
        displayNameEN: "Other",
        icon: "🧩",
        aliases: ["разное", "прочее", "other"]
    )

    private static let defaultSuggestedIcons = ["🧩", "🛒", "☕️", "🚕", "✈️", "🏠", "📱", "🎮", "💄", "🐾"]

    private static let semanticIconsByCategory: [CashbackCategory: [String]] = [
        .allPurchases: ["🛒", "💳", "✨"],
        .gasStation: ["⛽️", "🚗", "🛣️"],
        .supermarket: ["🛒", "🥑", "🥖"],
        .restaurant: ["🍽️", "🥗", "🍷"],
        .fastFood: ["🍕", "🍣", "🍔", "🍟", "🌮"],
        .coffeeShop: ["☕️", "🥐", "🍰"],
        .pharmacy: ["💊", "🩹", "🧴"],
        .healthcare: ["🩺", "🏥", "🦷"],
        .transport: ["🚇", "🚌", "🚉"],
        .taxi: ["🚖", "🚕", "🚘"],
        .carSharing: ["🚗", "🅿️", "🛣️"],
        .autoServices: ["🛠️", "🔧", "🚗"],
        .entertainment: ["🎮", "🎬", "🎟️"],
        .cinema: ["🎬", "🍿", "🎟️"],
        .travel: ["🧳", "✈️", "🏨"],
        .hotels: ["🏨", "🛏️", "🧳"],
        .airlines: ["✈️", "🧳", "🌍"],
        .railway: ["🚆", "🎫", "🧳"],
        .online: ["🌐", "💳", "📦"],
        .marketplaces: ["📦", "🛍️", "🚚"],
        .electronics: ["💻", "🖥️", "⌨️"],
        .homeGoods: ["🏠", "🪑", "🛋️"],
        .furniture: ["🛋️", "🪑", "🏠"],
        .clothing: ["👕", "👟", "🧥"],
        .shoes: ["👟", "🥿", "👞"],
        .beauty: ["💄", "💅", "🧴"],
        .sport: ["🏋️", "⚽️", "🏃"],
        .books: ["📚", "📖", "✏️"],
        .education: ["🎓", "📚", "✏️"],
        .kids: ["🧸", "🍼", "🎒"],
        .pets: ["🐾", "🐶", "🐱"],
        .telecom: ["📱", "☎️", "📶"],
        .internet: ["📶", "🌐", "🛜"],
        .utilities: ["💡", "🚿", "🔥"],
        .digitalServices: ["🖥️", "💻", "⌨️"],
        .subscriptions: ["🔁", "🎵", "📺"],
        .insurance: ["🛡️", "📄", "🚑"],
        .homeRepair: ["🔧", "🪛", "🏠"],
        .flowersGifts: ["🎁", "🌸", "💐"],
        .alcohol: ["🍷", "🍺", "🥂"],
        .other: ["🧩", "📌", "📦"]
    ]

    private static func heuristicIcons(for normalized: String) -> [String] {
        let tokens = tokenize(normalized)

        if tokens.contains(where: { matchesToken($0, candidates: ["пицц", "pizza", "пиццер"]) }) {
            return ["🍕", "🍔", "🍟"]
        }
        if tokens.contains(where: { matchesToken($0, candidates: ["суш", "ролл", "roll", "sushi"]) }) {
            return ["🍣", "🥢", "🍱"]
        }
        if tokens.contains(where: { matchesToken($0, candidates: ["коф", "coffee", "cafe", "latte", "капуч"]) }) {
            return ["☕️", "🥐", "🍰"]
        }
        if normalized.contains("комп") ||
            normalized.contains("ноут") ||
            normalized.contains("электрон") ||
            normalized.contains("гаджет") ||
            normalized.contains("computer") ||
            normalized.contains("laptop") ||
            normalized.contains("desktop") ||
            normalized.contains("tech") ||
            normalized.contains("pc") {
            return ["💻", "🖥️", "⌨️"]
        }
        if normalized.contains("спорт") || normalized.contains("sport") || normalized.contains("gym") {
            return ["🏋️", "⚽️", "🏃"]
        }
        if normalized.contains("дет") || normalized.contains("kids") || normalized.contains("baby") {
            return ["🧸", "🍼", "🎒"]
        }
        if normalized.contains("книг") || normalized.contains("book") {
            return ["📚", "📖", "✏️"]
        }
        if normalized.contains("цвет") || normalized.contains("flower") || normalized.contains("gift") {
            return ["🌸", "🎁", "💐"]
        }
        return []
    }

    private static func rankedMetadata(for normalizedQuery: String) -> [CashbackCategoryMetadata] {
        allMetadata
            .compactMap { metadata -> (CashbackCategoryMetadata, Int)? in
                let candidates = [metadata.displayNameRU, metadata.displayNameEN] + metadata.aliases
                let score = candidates
                    .map(normalize)
                    .map { matchScore(query: normalizedQuery, candidate: $0) }
                    .max() ?? 0
                return score > 0 ? (metadata, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.displayNameRU < rhs.0.displayNameRU
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private static func matchScore(query: String, candidate: String) -> Int {
        guard !query.isEmpty, !candidate.isEmpty else { return 0 }
        if query == candidate {
            return 400
        }
        if candidate.hasPrefix(query) {
            return 320
        }
        if query.hasPrefix(candidate) {
            return 260
        }

        let candidateWords = tokenize(candidate)
        let queryWords = tokenize(query)

        if candidateWords.contains(where: { $0.hasPrefix(query) }) {
            return 280
        }
        if queryWords.contains(where: { token in
            candidateWords.contains(where: { $0.hasPrefix(token) })
        }) {
            return 220
        }
        if candidate.contains(query) {
            return 180
        }
        if query.contains(candidate) {
            return 120
        }

        guard !candidateWords.isEmpty, !queryWords.isEmpty else { return 0 }

        var score = 0
        var matchedQueryTokens = 0
        var matchedCandidateTokens = Set<String>()

        for queryToken in queryWords {
            let bestTokenMatch = candidateWords
                .map { candidateToken in
                    (candidateToken, tokenMatchScore(queryToken: queryToken, candidateToken: candidateToken))
                }
                .max { lhs, rhs in lhs.1 < rhs.1 } ?? ("", 0)

            guard bestTokenMatch.1 > 0 else { continue }
            score += bestTokenMatch.1
            matchedQueryTokens += 1
            matchedCandidateTokens.insert(bestTokenMatch.0)
        }

        guard score > 0 else { return 0 }

        if matchedQueryTokens == queryWords.count {
            score += 90
        } else {
            score += matchedQueryTokens * 20
        }
        score += matchedCandidateTokens.count * 10

        return score
    }

    private static func tokenMatchScore(queryToken: String, candidateToken: String) -> Int {
        guard !queryToken.isEmpty, !candidateToken.isEmpty else { return 0 }
        if queryToken == candidateToken {
            return 160
        }
        if candidateToken.hasPrefix(queryToken) {
            return queryToken.count >= 3 ? 140 : 90
        }
        if queryToken.hasPrefix(candidateToken) {
            return candidateToken.count >= 3 ? 110 : 70
        }
        if candidateToken.contains(queryToken) || queryToken.contains(candidateToken) {
            return 60
        }
        return 0
    }

    private static func tokenize(_ value: String) -> [String] {
        value
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func matchesToken(_ token: String, candidates: [String]) -> Bool {
        candidates.contains { candidate in
            token.hasPrefix(candidate) || candidate.hasPrefix(token)
        }
    }

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
