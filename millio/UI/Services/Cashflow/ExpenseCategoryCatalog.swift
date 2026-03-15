//
//  ExpenseCategoryCatalog.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

enum ExpenseCategoryGroup: String, CaseIterable, Codable {
    case dailySpending = "daily_spending"
    case dining = "dining"
    case transport = "transport"
    case auto = "auto"
    case home = "home"
    case health = "health"
    case beauty = "beauty"
    case shopping = "shopping"
    case education = "education"
    case entertainment = "entertainment"
    case travel = "travel"
    case digital = "digital"
    case bills = "bills"
    case pets = "pets"
    case other = "other"
}

struct ExpenseCategoryMetadata: Equatable {
    let category: ExpenseCategory
    let group: ExpenseCategoryGroup
    let displayNameRU: String
    let displayNameEN: String
    let icon: String
    let aliases: [String]

    func localizedDisplayName(locale: Locale = .autoupdatingCurrent) -> String {
        ExpenseCategoryCatalog.preferredLanguageCode(for: locale) == "ru"
            ? displayNameRU
            : displayNameEN
    }
}

enum ExpenseCategoryCatalog {
    static let allMetadata: [ExpenseCategoryMetadata] = [
        .init(
            category: .groceries,
            group: .dailySpending,
            displayNameRU: "Продукты",
            displayNameEN: "Groceries",
            icon: "🛒",
            aliases: ["продукты", "супермаркеты", "grocery", "groceries", "supermarket", "food store", "вкусвилл", "пятерочка", "магнит"]
        ),
        .init(
            category: .cafe,
            group: .dining,
            displayNameRU: "Кафе",
            displayNameEN: "Cafes",
            icon: "☕️",
            aliases: ["кафе", "рестораны", "общепит", "restaurant", "restaurants", "cafe", "cafes", "dining"]
        ),
        .init(
            category: .fastFood,
            group: .dining,
            displayNameRU: "Фастфуд",
            displayNameEN: "Fast food",
            icon: "🍔",
            aliases: ["фастфуд", "fast food", "burger", "pizza", "kfc", "mcdonald", "burger king"]
        ),
        .init(
            category: .coffeeShops,
            group: .dining,
            displayNameRU: "Кофейни",
            displayNameEN: "Coffee shops",
            icon: "☕️",
            aliases: ["кофейня", "кофе", "coffee", "coffee shop", "starbucks", "costa", "surf coffee"]
        ),
        .init(
            category: .transport,
            group: .transport,
            displayNameRU: "Транспорт",
            displayNameEN: "Transport",
            icon: "🚇",
            aliases: ["транспорт", "метро", "автобус", "трамвай", "public transport", "transit", "bus", "metro"]
        ),
        .init(
            category: .taxi,
            group: .transport,
            displayNameRU: "Такси",
            displayNameEN: "Taxi",
            icon: "🚕",
            aliases: ["такси", "taxi", "ride hailing", "rideshare", "uber", "bolt", "yandex go", "яндекс go"]
        ),
        .init(
            category: .fuel,
            group: .auto,
            displayNameRU: "АЗС",
            displayNameEN: "Fuel",
            icon: "⛽️",
            aliases: ["топливо", "азс", "заправки", "бензин", "fuel", "gas station", "gas stations", "petrol", "petrol station", "газпромнефть", "лукойл"]
        ),
        .init(
            category: .carService,
            group: .auto,
            displayNameRU: "Сервис",
            displayNameEN: "Service",
            icon: "🛠️",
            aliases: ["автосервис", "сто", "ремонт авто", "car service", "auto repair", "maintenance", "шиномонтаж"]
        ),
        .init(
            category: .shopping,
            group: .shopping,
            displayNameRU: "Покупки",
            displayNameEN: "Shopping",
            icon: "🛍️",
            aliases: ["покупки", "shopping", "store", "mall", "retail"]
        ),
        .init(
            category: .marketplaces,
            group: .shopping,
            displayNameRU: "Маркетплейсы",
            displayNameEN: "Marketplaces",
            icon: "📦",
            aliases: ["маркетплейс", "маркетплейсы", "marketplace", "marketplaces", "ozon", "wb", "wildberries", "amazon"]
        ),
        .init(
            category: .clothing,
            group: .shopping,
            displayNameRU: "Одежда",
            displayNameEN: "Clothing",
            icon: "👕",
            aliases: ["одежда", "обувь", "fashion", "apparel", "clothing", "shoes", "lamoda"]
        ),
        .init(
            category: .homeGoods,
            group: .home,
            displayNameRU: "Дом",
            displayNameEN: "Home",
            icon: "🏠",
            aliases: ["дом", "товары для дома", "home", "home goods", "household", "ikea", "leroy merlin"]
        ),
        .init(
            category: .bills,
            group: .bills,
            displayNameRU: "Счета",
            displayNameEN: "Bills",
            icon: "🧾",
            aliases: ["счета", "bill", "bills", "аренда", "rent", "regular payment"]
        ),
        .init(
            category: .telecom,
            group: .bills,
            displayNameRU: "Связь",
            displayNameEN: "Telecom",
            icon: "📱",
            aliases: ["связь", "интернет", "telecom", "mobile", "isp", "wifi", "cellular", "мтс", "билайн", "мегафон"]
        ),
        .init(
            category: .utilities,
            group: .bills,
            displayNameRU: "ЖКХ и коммунальные",
            displayNameEN: "Utilities",
            icon: "💡",
            aliases: ["жкх", "коммунальные", "utilities", "electricity", "water", "gas utility", "electric bill"]
        ),
        .init(
            category: .health,
            group: .health,
            displayNameRU: "Здоровье",
            displayNameEN: "Health",
            icon: "💊",
            aliases: ["здоровье", "health", "doctor", "clinic"]
        ),
        .init(
            category: .pharmacies,
            group: .health,
            displayNameRU: "Аптеки",
            displayNameEN: "Pharmacies",
            icon: "💊",
            aliases: ["аптека", "аптеки", "pharmacy", "drugstore", "chemist"]
        ),
        .init(
            category: .medicalServices,
            group: .health,
            displayNameRU: "Медицина",
            displayNameEN: "Medical",
            icon: "🩺",
            aliases: ["медицинские услуги", "клиника", "врач", "стоматология", "medical", "healthcare", "clinic", "dental"]
        ),
        .init(
            category: .beauty,
            group: .beauty,
            displayNameRU: "Красота",
            displayNameEN: "Beauty",
            icon: "💄",
            aliases: ["красота", "косметика", "beauty", "cosmetics", "skincare", "parfum", "spa", "barber"]
        ),
        .init(
            category: .education,
            group: .education,
            displayNameRU: "Образование",
            displayNameEN: "Education",
            icon: "📚",
            aliases: ["образование", "курсы", "school", "tuition", "learning", "education", "университет"]
        ),
        .init(
            category: .entertainment,
            group: .entertainment,
            displayNameRU: "Развлечения",
            displayNameEN: "Entertainment",
            icon: "🎮",
            aliases: ["развлечения", "кино", "театр", "entertainment", "cinema", "movie", "concert", "steam"]
        ),
        .init(
            category: .travel,
            group: .travel,
            displayNameRU: "Путешествия",
            displayNameEN: "Travel",
            icon: "✈️",
            aliases: ["путешествия", "travel", "trip", "hotel", "отель", "авиабилет", "flight", "railway", "train ticket"]
        ),
        .init(
            category: .digitalServices,
            group: .digital,
            displayNameRU: "Сервисы",
            displayNameEN: "Digital",
            icon: "🖥️",
            aliases: ["цифровые сервисы", "digital services", "software", "apps", "saas", "app store"]
        ),
        .init(
            category: .subscriptions,
            group: .digital,
            displayNameRU: "Подписки",
            displayNameEN: "Subscriptions",
            icon: "🔁",
            aliases: ["подписки", "subscription", "subscriptions", "netflix", "spotify", "youtube premium", "icloud"]
        ),
        .init(
            category: .pets,
            group: .pets,
            displayNameRU: "Товары для животных",
            displayNameEN: "Pet goods",
            icon: "🐾",
            aliases: ["питомцы", "зоомагазин", "pets", "pet store", "veterinary", "ветеринар"]
        ),
        .init(
            category: .other,
            group: .other,
            displayNameRU: "Разное",
            displayNameEN: "Other",
            icon: "🧩",
            aliases: ["разное", "прочее", "other", "misc", "unknown", "uncategorized"]
        )
    ]

    private static let metadataByCategory = Dictionary(uniqueKeysWithValues: allMetadata.map { ($0.category, $0) })
    private static let metadataByRawValue = Dictionary(uniqueKeysWithValues: allMetadata.map { ($0.category.rawValue, $0) })

    static func metadata(for category: ExpenseCategory) -> ExpenseCategoryMetadata {
        metadataByCategory[category] ?? fallbackMetadata
    }

    static func metadata(forRawValue rawValue: String) -> ExpenseCategoryMetadata? {
        metadataByRawValue[rawValue]
    }

    static func aliases(for category: ExpenseCategory) -> [String] {
        metadata(for: category).aliases
    }

    static func matchesSearch(rawValue: String, query: String, locale: Locale = .autoupdatingCurrent) -> Bool {
        let normalizedQuery = normalizeSearchValue(query)
        guard !normalizedQuery.isEmpty else { return true }
        guard let metadata = metadata(forRawValue: rawValue) else { return false }

        let candidates = [
            metadata.localizedDisplayName(locale: locale),
            metadata.displayNameRU,
            metadata.displayNameEN,
            rawValue
        ] + metadata.aliases

        return candidates
            .map(normalizeSearchValue)
            .contains { candidate in
                candidate.contains(normalizedQuery) || normalizedQuery.contains(candidate)
            }
    }

    static func suggestedIcons(for name: String) -> [String] {
        let normalized = normalizeSearchValue(name)
        guard !normalized.isEmpty else {
            return Array(defaultSuggestedIcons.prefix(8))
        }

        let matchedMetadata = allMetadata.first { metadata in
            let candidates = [metadata.displayNameRU, metadata.displayNameEN] + metadata.aliases
            return candidates.map(normalizeSearchValue).contains { candidate in
                candidate.contains(normalized) || normalized.contains(candidate)
            }
        }

        let semanticIcons = matchedMetadata.map { semanticIconsByCategory[$0.category] ?? [] } ?? heuristicIcons(for: normalized)
        let icon = matchedMetadata?.icon
        var combined: [String] = []
        if let icon {
            combined.append(icon)
        }
        combined.append(contentsOf: semanticIcons)
        combined.append(contentsOf: defaultSuggestedIcons)

        var unique: [String] = []
        for item in combined where !unique.contains(item) {
            unique.append(item)
        }
        return Array(unique.prefix(10))
    }

    static func preferredLanguageCode(for locale: Locale) -> String {
        if #available(iOS 16.0, *),
           let code = locale.language.languageCode?.identifier,
           !code.isEmpty {
            return code.lowercased()
        }

        if let code = locale.identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() {
            return String(code)
        }

        return "en"
    }

    private static let fallbackMetadata = ExpenseCategoryMetadata(
        category: .other,
        group: .other,
        displayNameRU: "Разное",
        displayNameEN: "Other",
        icon: "🧩",
        aliases: ["разное", "прочее", "other", "unknown"]
    )

    private static let defaultSuggestedIcons = ["🧩", "🛒", "☕️", "🚕", "✈️", "🏠", "📱", "🎮", "💄", "🐾"]

    private static let semanticIconsByCategory: [ExpenseCategory: [String]] = [
        .groceries: ["🛒", "🥑", "🥖"],
        .cafe: ["☕️", "🍽️", "🥗"],
        .fastFood: ["🍔", "🍟", "🌮"],
        .coffeeShops: ["☕️", "🥐", "🍰"],
        .transport: ["🚇", "🚌", "🚉"],
        .taxi: ["🚕", "🚖", "🚘"],
        .fuel: ["⛽️", "🚗", "🛣️"],
        .carService: ["🛠️", "🔧", "🚗"],
        .shopping: ["🛍️", "🛒", "🎁"],
        .marketplaces: ["📦", "🛍️", "🚚"],
        .clothing: ["👕", "👟", "🧥"],
        .homeGoods: ["🏠", "🪑", "🛋️"],
        .bills: ["🧾", "💳", "🏦"],
        .telecom: ["📱", "📶", "☎️"],
        .utilities: ["💡", "🚿", "🔥"],
        .health: ["💊", "🩺", "❤️"],
        .pharmacies: ["💊", "🩹", "🧴"],
        .medicalServices: ["🩺", "🏥", "🦷"],
        .beauty: ["💄", "💅", "🧴"],
        .education: ["📚", "🎓", "✏️"],
        .entertainment: ["🎮", "🎬", "🎟️"],
        .travel: ["✈️", "🏨", "🧳"],
        .digitalServices: ["🖥️", "📲", "⌨️"],
        .subscriptions: ["🔁", "🎵", "📺"],
        .pets: ["🐾", "🐶", "🐱"],
        .other: ["🧩", "📌", "📦"]
    ]

    private static func heuristicIcons(for normalized: String) -> [String] {
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

    private static func normalizeSearchValue(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
