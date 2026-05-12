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
    case housing = "housing"
    case bills = "bills"
    case health = "health"
    case beauty = "beauty"
    case shopping = "shopping"
    case education = "education"
    case entertainment = "entertainment"
    case travel = "travel"
    case subscriptions = "subscriptions"
    case pets = "pets"
    case insurance = "insurance"
    case sports = "sports"
    case taxesFees = "taxes_fees"
    case transfers = "transfers"
    case other = "other"
}

struct ExpenseCategoryMetadata: Equatable {
    let category: ExpenseCategory
    let group: ExpenseCategoryGroup
    let displayNameRU: String
    let displayNameEN: String
    let icon: String
    let aliases: [String]

    func localizedDisplayName(locale: Locale = AppLocalization.currentAppLocale) -> String {
        switch ExpenseCategoryCatalog.preferredLanguageCode(for: locale) {
        case "ru":
            return displayNameRU
        case "zh":
            return ExpenseCategoryCatalog.chineseDisplayName(for: category) ?? displayNameEN
        case "de":
            return ExpenseCategoryCatalog.germanDisplayName(for: category) ?? displayNameEN
        case "es":
            return ExpenseCategoryCatalog.spanishDisplayName(for: category) ?? displayNameEN
        default:
            return displayNameEN
        }
    }
}

enum ExpenseCategoryCatalog {
    /// Visible system categories define the current product taxonomy.
    /// Legacy categories remain below for display, import, and data compatibility.
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
            category: .dining,
            group: .dining,
            displayNameRU: "Еда вне дома",
            displayNameEN: "Dining out",
            icon: "🍽️",
            aliases: [
                "еда вне дома", "кафе", "кафешка", "ресторан", "рестораны", "рестик", "рестики", "рестороны", "ресторан",
                "общепит", "кофейня", "кофе", "coffee shop",
                "coffee", "cafe", "cafes", "restaurant", "restaurants", "dining", "dining out",
                "fast food", "фастфуд", "быстрая еда", "пицца", "роллы", "суши", "pizza", "burger", "sushi", "rolls", "доставка еды"
            ]
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
            displayNameRU: "Топливо",
            displayNameEN: "Fuel",
            icon: "⛽️",
            aliases: ["топливо", "азс", "заправки", "бензин", "fuel", "gas station", "gas stations", "petrol", "petrol station", "газпромнефть", "лукойл"]
        ),
        .init(
            category: .carService,
            group: .auto,
            displayNameRU: "Автосервис",
            displayNameEN: "Car service",
            icon: "🔧",
            aliases: ["автосервис", "сто", "ремонт авто", "car service", "auto repair", "maintenance", "шиномонтаж"]
        ),
        .init(
            category: .housing,
            group: .housing,
            displayNameRU: "Жилье",
            displayNameEN: "Housing",
            icon: "🏠",
            aliases: ["жилье", "жильё", "аренда", "rent", "mortgage", "ипотека", "home", "housing", "apartment", "квартира"]
        ),
        .init(
            category: .utilities,
            group: .bills,
            displayNameRU: "Коммунальные",
            displayNameEN: "Utilities",
            icon: "💡",
            aliases: ["жкх", "коммунальные", "utilities", "electricity", "water", "gas utility", "electric bill"]
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
            category: .health,
            group: .health,
            displayNameRU: "Здоровье",
            displayNameEN: "Health",
            icon: "🩺",
            aliases: ["здоровье", "health", "doctor", "clinic", "medical", "healthcare", "dental", "стоматология", "врач", "клиника"]
        ),
        .init(
            category: .pharmacy,
            group: .health,
            displayNameRU: "Аптека",
            displayNameEN: "Pharmacy",
            icon: "💊",
            aliases: ["аптека", "аптеки", "pharmacy", "drugstore", "chemist"]
        ),
        .init(
            category: .shopping,
            group: .shopping,
            displayNameRU: "Покупки",
            displayNameEN: "Shopping",
            icon: "🛍️",
            aliases: ["покупки", "shopping", "store", "mall", "retail", "маркетплейс", "маркетплейсы", "marketplace", "marketplaces", "ozon", "wb", "wildberries", "amazon"]
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
            category: .electronics,
            group: .shopping,
            displayNameRU: "Электроника",
            displayNameEN: "Electronics",
            icon: "💻",
            aliases: [
                "электроника", "техника", "гаджеты", "gadgets", "electronics", "tech",
                "компьютер", "компьютеры", "комп", "компы", "компьютерная техника",
                "ноутбук", "ноут", "макбук", "laptop", "computer", "computers", "pc", "desktop", "macbook"
            ]
        ),
        .init(
            category: .homeGoods,
            group: .housing,
            displayNameRU: "Товары для дома",
            displayNameEN: "Home goods",
            icon: "🪑",
            aliases: ["дом", "товары для дома", "home goods", "household", "ikea", "leroy merlin", "furniture", "мебель"]
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
            category: .subscriptions,
            group: .subscriptions,
            displayNameRU: "Подписки",
            displayNameEN: "Subscriptions",
            icon: "🔁",
            aliases: ["подписки", "subscription", "subscriptions", "netflix", "spotify", "youtube premium", "icloud", "digital services", "software", "saas", "app store"]
        ),
        .init(
            category: .pets,
            group: .pets,
            displayNameRU: "Животные",
            displayNameEN: "Pets",
            icon: "🐾",
            aliases: ["питомцы", "зоомагазин", "pets", "pet store", "veterinary", "ветеринар"]
        ),
        .init(
            category: .gifts,
            group: .shopping,
            displayNameRU: "Подарки",
            displayNameEN: "Gifts",
            icon: "🎁",
            aliases: ["подарки", "подарок", "gifts", "gift", "flowers", "цветы", "flowers and gifts"]
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
            category: .insurance,
            group: .insurance,
            displayNameRU: "Страхование",
            displayNameEN: "Insurance",
            icon: "🛡️",
            aliases: ["страхование", "insurance", "insured", "осаго", "каско", "travel insurance"]
        ),
        .init(
            category: .taxesFees,
            group: .taxesFees,
            displayNameRU: "Налоги и комиссии",
            displayNameEN: "Taxes & fees",
            icon: "🏛️",
            aliases: ["налоги", "комиссии", "fees", "taxes", "bank fee", "service fee", "госпошлина", "налог"]
        ),
        .init(
            category: .transfers,
            group: .transfers,
            displayNameRU: "Переводы",
            displayNameEN: "Transfers",
            icon: "🔄",
            aliases: [
                "перевод", "переводы", "перевод себе", "сбп", "sbp", "p2p", "card to card",
                "между счетами", "между счетов", "перевод между счетами", "transfer", "transfers"
            ]
        ),
        .init(
            category: .sports,
            group: .sports,
            displayNameRU: "Спорт и фитнес",
            displayNameEN: "Sports & fitness",
            icon: "🏋️",
            aliases: ["спорт", "фитнес", "спортзал", "зал", "тренировка", "тренировки", "gym", "fitness", "sport", "sports", "workout", "training", "бассейн", "swimming", "бег", "running", "йога", "yoga", "football", "футбол"]
        ),
        .init(
            category: .other,
            group: .other,
            displayNameRU: "Другое",
            displayNameEN: "Other",
            icon: "🧩",
            aliases: ["другое", "разное", "прочее", "other", "misc", "unknown", "uncategorized"]
        ),

        // Legacy categories kept to resolve and display old saved raw values.
        .init(
            category: .cafe,
            group: .dining,
            displayNameRU: "Кафе",
            displayNameEN: "Cafes",
            icon: "☕️",
            aliases: ["кафе", "cafe", "cafes"]
        ),
        .init(
            category: .fastFood,
            group: .dining,
            displayNameRU: "Фастфуд",
            displayNameEN: "Fast food",
            icon: "🍔",
            aliases: ["фастфуд", "fast food", "burger", "pizza", "пицца", "бургер", "шаверма", "шаурма", "kfc", "mcdonald"]
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
            category: .marketplaces,
            group: .shopping,
            displayNameRU: "Маркетплейсы",
            displayNameEN: "Marketplaces",
            icon: "📦",
            aliases: ["маркетплейс", "маркетплейсы", "marketplace", "marketplaces", "ozon", "wb", "wildberries", "amazon"]
        ),
        .init(
            category: .bills,
            group: .bills,
            displayNameRU: "Счета",
            displayNameEN: "Bills",
            icon: "🧾",
            aliases: ["счета", "bill", "bills", "regular payment"]
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
            category: .digitalServices,
            group: .subscriptions,
            displayNameRU: "Сервисы",
            displayNameEN: "Digital",
            icon: "🖥️",
            aliases: ["цифровые сервисы", "digital services", "software", "apps", "saas", "app store"]
        )
    ]

    private static let metadataByCategory = Dictionary(uniqueKeysWithValues: allMetadata.map { ($0.category, $0) })
    private static let metadataByRawValue = Dictionary(uniqueKeysWithValues: allMetadata.map { ($0.category.rawValue, $0) })

    static func chineseDisplayName(for category: ExpenseCategory) -> String? {
        switch category {
        case .groceries:
            return "商超购物"
        case .dining:
            return "外食"
        case .transport:
            return "交通"
        case .taxi:
            return "打车"
        case .fuel:
            return "加油"
        case .carService:
            return "汽车服务"
        case .housing:
            return "住房"
        case .utilities:
            return "水电煤"
        case .telecom:
            return "通信"
        case .health:
            return "健康"
        case .pharmacy:
            return "药房"
        case .shopping:
            return "购物"
        case .clothing:
            return "服饰"
        case .electronics:
            return "电子产品"
        case .homeGoods:
            return "家居用品"
        case .education:
            return "教育"
        case .entertainment:
            return "娱乐"
        case .travel:
            return "旅行"
        case .subscriptions:
            return "订阅"
        case .pets:
            return "宠物"
        case .gifts:
            return "礼物"
        case .beauty:
            return "美容"
        case .insurance:
            return "保险"
        case .taxesFees:
            return "税费"
        case .sports:
            return "运动健身"
        case .transfers:
            return "转账"
        case .other:
            return "其他"
        case .cafe:
            return "咖啡馆"
        case .fastFood:
            return "快餐"
        case .coffeeShops:
            return "咖啡店"
        case .marketplaces:
            return "电商平台"
        case .bills:
            return "账单"
        case .pharmacies:
            return "药店"
        case .medicalServices:
            return "医疗服务"
        case .digitalServices:
            return "数字服务"
        }
    }

    static func germanDisplayName(for category: ExpenseCategory) -> String? {
        switch category {
        case .groceries:        return "Lebensmittel"
        case .dining:           return "Essen gehen"
        case .transport:        return "Nahverkehr"
        case .taxi:             return "Taxi"
        case .fuel:             return "Tankstelle"
        case .carService:       return "Autowerkstatt"
        case .housing:          return "Wohnen"
        case .utilities:        return "Nebenkosten"
        case .telecom:          return "Telekommunikation"
        case .health:           return "Gesundheit"
        case .pharmacy:         return "Apotheke"
        case .shopping:         return "Einkaufen"
        case .clothing:         return "Kleidung"
        case .electronics:      return "Elektronik"
        case .homeGoods:        return "Haushaltswaren"
        case .education:        return "Bildung"
        case .entertainment:    return "Unterhaltung"
        case .travel:           return "Reisen"
        case .subscriptions:    return "Abonnements"
        case .pets:             return "Haustiere"
        case .gifts:            return "Geschenke"
        case .beauty:           return "Beauty"
        case .insurance:        return "Versicherung"
        case .taxesFees:        return "Steuern & Gebühren"
        case .sports:           return "Sport & Fitness"
        case .transfers:        return "Überweisungen"
        case .other:            return "Sonstiges"
        case .cafe:             return "Café"
        case .fastFood:         return "Fast Food"
        case .coffeeShops:      return "Kaffeehaus"
        case .marketplaces:     return "Online-Marktplätze"
        case .bills:            return "Rechnungen"
        case .pharmacies:       return "Apotheken"
        case .medicalServices:  return "Medizinische Leistungen"
        case .digitalServices:  return "Digitale Dienste"
        }
    }

    static func spanishDisplayName(for category: ExpenseCategory) -> String? {
        switch category {
        case .groceries:        return "Supermercado"
        case .dining:           return "Restaurantes"
        case .transport:        return "Transporte público"
        case .taxi:             return "Taxi"
        case .fuel:             return "Gasolinera"
        case .carService:       return "Taller mecánico"
        case .housing:          return "Vivienda"
        case .utilities:        return "Suministros"
        case .telecom:          return "Telecomunicaciones"
        case .health:           return "Salud"
        case .pharmacy:         return "Farmacia"
        case .shopping:         return "Compras"
        case .clothing:         return "Ropa"
        case .electronics:      return "Electrónica"
        case .homeGoods:        return "Artículos del hogar"
        case .education:        return "Educación"
        case .entertainment:    return "Entretenimiento"
        case .travel:           return "Viajes"
        case .subscriptions:    return "Suscripciones"
        case .pets:             return "Mascotas"
        case .gifts:            return "Regalos"
        case .beauty:           return "Belleza"
        case .insurance:        return "Seguros"
        case .taxesFees:        return "Impuestos y tasas"
        case .sports:           return "Deporte y fitness"
        case .transfers:        return "Transferencias"
        case .other:            return "Otros"
        case .cafe:             return "Cafetería"
        case .fastFood:         return "Comida rápida"
        case .coffeeShops:      return "Cafés"
        case .marketplaces:     return "Tiendas online"
        case .bills:            return "Facturas"
        case .pharmacies:       return "Farmacias"
        case .medicalServices:  return "Servicios médicos"
        case .digitalServices:  return "Servicios digitales"
        }
    }

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

        let candidates = metadataCandidates(forRawValue: rawValue, locale: locale)
        guard !candidates.isEmpty else { return false }

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

        let matchedMetadata = rankedMetadata(for: normalized)
        let heuristicIcons = heuristicIcons(for: normalized)
        let semanticIcons = matchedMetadata
            .prefix(3)
            .flatMap { semanticIconsByCategory[$0.category] ?? [] }
        let icon = matchedMetadata.first?.icon
        var combined: [String] = []
        if let icon {
            combined.append(icon)
        }
        // Exact food/token heuristics should outrank broad legacy category matches like fast food.
        combined.append(contentsOf: heuristicIcons)
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
        displayNameRU: "Другое",
        displayNameEN: "Other",
        icon: "🧩",
        aliases: ["другое", "разное", "прочее", "other", "unknown"]
    )

    private static let defaultSuggestedIcons = ["🧩", "🛒", "🍽️", "🚕", "✈️", "🏠", "📱", "🎮", "💄", "🐾"]

    private static let semanticIconsByCategory: [ExpenseCategory: [String]] = [
        .groceries: ["🛒", "🥑", "🥖"],
        .dining: ["🍽️", "☕️", "🍔", "🍣"],
        .transport: ["🚇", "🚌", "🚉"],
        .taxi: ["🚕", "🚖", "🚘"],
        .fuel: ["⛽️", "🚗", "🛣️"],
        .carService: ["🔧", "🛠️", "🚗"],
        .housing: ["🏠", "🔑", "🛋️"],
        .utilities: ["💡", "🚿", "🔥"],
        .telecom: ["📱", "📶", "☎️"],
        .health: ["🩺", "❤️", "🏥"],
        .pharmacy: ["💊", "🩹", "🧴"],
        .shopping: ["🛍️", "🛒", "📦"],
        .clothing: ["👕", "👟", "🧥"],
        .electronics: ["💻", "🖥️", "⌨️"],
        .homeGoods: ["🪑", "🏠", "🛋️"],
        .education: ["📚", "🎓", "✏️"],
        .entertainment: ["🎮", "🎬", "🎟️"],
        .travel: ["✈️", "🏨", "🧳"],
        .subscriptions: ["🔁", "🎵", "📺"],
        .pets: ["🐾", "🐶", "🐱"],
        .gifts: ["🎁", "💐", "🌸"],
        .beauty: ["💄", "💅", "🧴"],
        .insurance: ["🛡️", "📋", "🚘"],
        .sports: ["🏋️", "🏃", "⚽️"],
        .taxesFees: ["🏛️", "🧾", "💸"],
        .transfers: ["🔄", "💳", "🏦"],
        .other: ["🧩", "📌", "📦"]
    ]

    private static func metadataCandidates(forRawValue rawValue: String, locale: Locale) -> [String] {
        let resolvedRaw = ExpenseCategory.canonicalRawValue(rawValue)
        var metadataItems: [ExpenseCategoryMetadata] = []

        if let currentMetadata = metadata(forRawValue: resolvedRaw) {
            metadataItems.append(currentMetadata)
        }
        if resolvedRaw != rawValue, let legacyMetadata = metadata(forRawValue: rawValue) {
            metadataItems.append(legacyMetadata)
        }

        return metadataItems.flatMap { metadata in
            [
                metadata.localizedDisplayName(locale: locale),
                metadata.displayNameRU,
                metadata.displayNameEN,
                rawValue,
                resolvedRaw
            ] + metadata.aliases
        }
    }

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
        if normalized.contains("страх") || normalized.contains("insurance") {
            return ["🛡️", "📋", "💸"]
        }
        if normalized.contains("налог") || normalized.contains("комисс") || normalized.contains("tax") || normalized.contains("fee") {
            return ["🏛️", "🧾", "💸"]
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

    private static func rankedMetadata(for normalizedQuery: String) -> [ExpenseCategoryMetadata] {
        allMetadata
            .compactMap { metadata -> (ExpenseCategoryMetadata, Int)? in
                let candidates = [metadata.displayNameRU, metadata.displayNameEN] + metadata.aliases
                let score = candidates
                    .map(normalizeSearchValue)
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
