//
//  CashbackCategoryCatalog.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

struct CashbackCategoryMetadata: Equatable {
    let category: CashbackCategory
    let localizationKey: String
    let fallbackDisplayName: String
    let icon: String
    let aliases: [String]

    func localizedDisplayName(locale: Locale = AppLocalization.currentAppLocale) -> String {
        CashbackL10n.text(localizationKey, locale: locale, fallback: fallbackDisplayName)
    }

    func searchableNames(locales: [Locale] = CashbackL10n.supportedLocales) -> [String] {
        locales.map { localizedDisplayName(locale: $0) }
    }
}

enum CashbackCategoryCatalog {
    static let allMetadata: [CashbackCategoryMetadata] = [
        .init(category: .allPurchases, localizationKey: "cashback.category.all_purchases", fallbackDisplayName: "All purchases", icon: "🛒", aliases: ["все покупки", "all purchases", "base cashback"]),
        .init(category: .gasStation, localizationKey: "cashback.category.gas_station", fallbackDisplayName: "Gas stations", icon: "⛽️", aliases: ["топливо", "азс", "заправки", "fuel", "gas station", "gas stations", "petrol"]),
        .init(category: .supermarket, localizationKey: "cashback.category.supermarket", fallbackDisplayName: "Groceries", icon: "🛒", aliases: ["продукты", "супермаркеты", "groceries", "grocery", "supermarket", "supermarkets", "вкусвилл", "пятерочка"]),
        .init(category: .restaurant, localizationKey: "cashback.category.restaurant", fallbackDisplayName: "Restaurants", icon: "🍽️", aliases: ["кафе", "рестораны", "restaurants", "restaurant", "dining"]),
        .init(category: .fastFood, localizationKey: "cashback.category.fast_food", fallbackDisplayName: "Fast food", icon: "🍔", aliases: ["фастфуд", "быстрая еда", "fast food", "burger", "pizza", "пицца", "пиццерия", "роллы", "суши", "бургер", "шаверма", "шаурма", "доставка еды"]),
        .init(category: .coffeeShop, localizationKey: "cashback.category.coffee_shop", fallbackDisplayName: "Coffee shops", icon: "☕️", aliases: ["кофейня", "кофе", "coffee", "coffee shop"]),
        .init(category: .pharmacy, localizationKey: "cashback.category.pharmacy", fallbackDisplayName: "Pharmacies", icon: "💊", aliases: ["аптека", "аптеки", "pharmacy", "drugstore"]),
        .init(category: .healthcare, localizationKey: "cashback.category.healthcare", fallbackDisplayName: "Healthcare", icon: "🩺", aliases: ["медицина", "медицинские услуги", "клиника", "врач", "medical", "medical services", "healthcare", "dental"]),
        .init(category: .transport, localizationKey: "cashback.category.transport", fallbackDisplayName: "Transport", icon: "🚕", aliases: ["транспорт", "metro", "public transport", "bus", "transit"]),
        .init(category: .taxi, localizationKey: "cashback.category.taxi", fallbackDisplayName: "Taxi", icon: "🚖", aliases: ["такси", "taxi", "uber", "yandex go", "rideshare"]),
        .init(category: .carSharing, localizationKey: "cashback.category.car_sharing", fallbackDisplayName: "Car sharing", icon: "🚗", aliases: ["каршеринг", "car sharing", "carsharing"]),
        .init(category: .autoServices, localizationKey: "cashback.category.auto_services", fallbackDisplayName: "Auto", icon: "🛠️", aliases: ["авто", "автосервис", "сто", "car service", "auto repair", "maintenance"]),
        .init(category: .entertainment, localizationKey: "cashback.category.entertainment", fallbackDisplayName: "Entertainment", icon: "🎮", aliases: ["развлечения", "entertainment", "cinema", "movie", "theatre"]),
        .init(category: .cinema, localizationKey: "cashback.category.cinema", fallbackDisplayName: "Movies", icon: "🎬", aliases: ["кино", "cinema", "movie"]),
        .init(category: .travel, localizationKey: "cashback.category.travel", fallbackDisplayName: "Travel", icon: "🧳", aliases: ["путешествия", "travel", "trip"]),
        .init(category: .hotels, localizationKey: "cashback.category.hotels", fallbackDisplayName: "Hotels", icon: "🏨", aliases: ["отели", "hotel", "hotels", "lodging"]),
        .init(category: .airlines, localizationKey: "cashback.category.airlines", fallbackDisplayName: "Airfare", icon: "✈️", aliases: ["авиабилеты", "flights", "airline", "airfare"]),
        .init(category: .railway, localizationKey: "cashback.category.railway", fallbackDisplayName: "Rail Tickets", icon: "🚆", aliases: ["поезда", "railway", "train tickets", "rail"]),
        .init(category: .online, localizationKey: "cashback.category.online", fallbackDisplayName: "Online Shopping", icon: "🌐", aliases: ["онлайн", "online", "internet", "ecommerce"]),
        .init(category: .marketplaces, localizationKey: "cashback.category.marketplaces", fallbackDisplayName: "Marketplaces", icon: "📦", aliases: ["маркетплейсы", "marketplace", "ozon", "wb", "wildberries", "amazon"]),
        .init(category: .electronics, localizationKey: "cashback.category.electronics", fallbackDisplayName: "Electronics", icon: "💻", aliases: ["техника", "electronics", "gadgets", "electronic"]),
        .init(category: .homeGoods, localizationKey: "cashback.category.home_goods", fallbackDisplayName: "Home goods", icon: "🏠", aliases: ["дом", "home goods", "товары для дома", "household"]),
        .init(category: .furniture, localizationKey: "cashback.category.furniture", fallbackDisplayName: "Furniture", icon: "🛋️", aliases: ["мебель", "furniture"]),
        .init(category: .clothing, localizationKey: "cashback.category.clothing", fallbackDisplayName: "Clothing", icon: "👕", aliases: ["одежда", "clothing", "fashion", "apparel"]),
        .init(category: .shoes, localizationKey: "cashback.category.shoes", fallbackDisplayName: "Shoes", icon: "👟", aliases: ["обувь", "shoes", "footwear"]),
        .init(category: .beauty, localizationKey: "cashback.category.beauty", fallbackDisplayName: "Beauty & Personal Care", icon: "💄", aliases: ["красота", "beauty", "cosmetics", "spa", "barber"]),
        .init(category: .sport, localizationKey: "cashback.category.sport", fallbackDisplayName: "Sporting Goods", icon: "🏋️", aliases: ["спорт", "gym", "fitness", "sport"]),
        .init(category: .books, localizationKey: "cashback.category.books", fallbackDisplayName: "Books", icon: "📚", aliases: ["книги", "books", "bookstore"]),
        .init(category: .education, localizationKey: "cashback.category.education", fallbackDisplayName: "Education", icon: "🎓", aliases: ["образование", "education", "courses", "tuition"]),
        .init(category: .kids, localizationKey: "cashback.category.kids", fallbackDisplayName: "Kids & Baby", icon: "🧸", aliases: ["дети", "kids", "baby", "toys"]),
        .init(category: .pets, localizationKey: "cashback.category.pets", fallbackDisplayName: "Pet supplies", icon: "🐾", aliases: ["питомцы", "pets", "pet store", "veterinary"]),
        .init(category: .telecom, localizationKey: "cashback.category.telecom", fallbackDisplayName: "Mobile services", icon: "📱", aliases: ["связь", "telecom", "mobile", "cellular"]),
        .init(category: .internet, localizationKey: "cashback.category.internet", fallbackDisplayName: "Internet", icon: "📶", aliases: ["интернет", "internet", "wifi", "isp"]),
        .init(category: .utilities, localizationKey: "cashback.category.utilities", fallbackDisplayName: "Utilities & Bills", icon: "💡", aliases: ["жкх", "коммунальные", "utilities", "electricity", "water"]),
        .init(category: .digitalServices, localizationKey: "cashback.category.digital_services", fallbackDisplayName: "Digital services", icon: "🖥️", aliases: ["сервисы", "digital services", "software", "apps", "saas"]),
        .init(category: .subscriptions, localizationKey: "cashback.category.subscriptions", fallbackDisplayName: "Subscriptions", icon: "🔁", aliases: ["подписки", "subscription", "subscriptions", "netflix", "spotify"]),
        .init(category: .insurance, localizationKey: "cashback.category.insurance", fallbackDisplayName: "Insurance", icon: "🛡️", aliases: ["страхование", "insurance"]),
        .init(category: .homeRepair, localizationKey: "cashback.category.home_repair", fallbackDisplayName: "Home repair", icon: "🔧", aliases: ["ремонт", "diy", "home repair", "hardware"]),
        .init(category: .flowersGifts, localizationKey: "cashback.category.flowers_gifts", fallbackDisplayName: "Flowers and gifts", icon: "🎁", aliases: ["подарки", "цветы", "gift", "flowers"]),
        .init(category: .alcohol, localizationKey: "cashback.category.alcohol", fallbackDisplayName: "Liquor Stores", icon: "🍷", aliases: ["алкоголь", "alcohol", "wine", "beer"]),
        .init(category: .other, localizationKey: "cashback.category.other", fallbackDisplayName: "Other", icon: "🧩", aliases: ["разное", "прочее", "other", "misc", "unknown"])
    ]

    private static let metadataByCategory = Dictionary(uniqueKeysWithValues: allMetadata.map { ($0.category, $0) })
    private static let metadataByRawValue = Dictionary(uniqueKeysWithValues: allMetadata.map { ($0.category.rawValue, $0) })

    static func metadata(for category: CashbackCategory) -> CashbackCategoryMetadata {
        metadataByCategory[category] ?? fallbackMetadata
    }

    static func metadata(forRawValue rawValue: String) -> CashbackCategoryMetadata? {
        metadataByRawValue[rawValue]
    }

    static func matchesSearch(rawValue: String, query: String, locale: Locale = AppLocalization.currentAppLocale) -> Bool {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return true }
        guard let metadata = metadata(forRawValue: rawValue) else { return false }

        let candidates = metadata.searchableNames(locales: [locale] + CashbackL10n.supportedLocales) + [rawValue] + metadata.aliases
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
        localizationKey: "cashback.category.other",
        fallbackDisplayName: "Other",
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
                let candidates = metadata.searchableNames() + metadata.aliases
                let score = candidates
                    .map(normalize)
                    .map { matchScore(query: normalizedQuery, candidate: $0) }
                    .max() ?? 0
                return score > 0 ? (metadata, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.fallbackDisplayName < rhs.0.fallbackDisplayName
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
