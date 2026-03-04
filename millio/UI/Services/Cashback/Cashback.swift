//
//  Cashback.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Категория кешбэка.
/// Держим расширенный системный каталог (35-40 категорий) под базовые сценарии РФ.
enum CashbackCategory: String, Codable, CaseIterable {
    case gasStation = "gas_station"
    case supermarket = "supermarket"
    case restaurant = "restaurant"
    case fastFood = "fast_food"
    case coffeeShop = "coffee_shop"
    case pharmacy = "pharmacy"
    case healthcare = "healthcare"
    case transport = "transport"
    case taxi = "taxi"
    case carSharing = "car_sharing"
    case autoServices = "auto_services"
    case entertainment = "entertainment"
    case cinema = "cinema"
    case travel = "travel"
    case hotels = "hotels"
    case airlines = "airlines"
    case railway = "railway"
    case online = "online"
    case marketplaces = "marketplaces"
    case electronics = "electronics"
    case homeGoods = "home_goods"
    case furniture = "furniture"
    case clothing = "clothing"
    case shoes = "shoes"
    case beauty = "beauty"
    case sport = "sport"
    case books = "books"
    case education = "education"
    case kids = "kids"
    case pets = "pets"
    case telecom = "telecom"
    case internet = "internet"
    case utilities = "utilities"
    case digitalServices = "digital_services"
    case subscriptions = "subscriptions"
    case insurance = "insurance"
    case homeRepair = "home_repair"
    case flowersGifts = "flowers_gifts"
    case alcohol = "alcohol"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .gasStation: return "Заправки"
        case .supermarket: return "Супермаркеты"
        case .restaurant: return "Рестораны"
        case .fastFood: return "Фастфуд"
        case .coffeeShop: return "Кофейни"
        case .pharmacy: return "Аптеки"
        case .healthcare: return "Медицина"
        case .transport: return "Транспорт"
        case .taxi: return "Такси"
        case .carSharing: return "Каршеринг"
        case .autoServices: return "Автосервисы"
        case .entertainment: return "Развлечения"
        case .cinema: return "Кино"
        case .travel: return "Путешествия"
        case .hotels: return "Отели"
        case .airlines: return "Авиабилеты"
        case .railway: return "Ж/д билеты"
        case .online: return "Онлайн"
        case .marketplaces: return "Маркетплейсы"
        case .electronics: return "Электроника"
        case .homeGoods: return "Товары для дома"
        case .furniture: return "Мебель"
        case .clothing: return "Одежда"
        case .shoes: return "Обувь"
        case .beauty: return "Красота"
        case .sport: return "Спорттовары"
        case .books: return "Книги"
        case .education: return "Образование"
        case .kids: return "Детские товары"
        case .pets: return "Зоотовары"
        case .telecom: return "Связь"
        case .internet: return "Интернет"
        case .utilities: return "ЖКХ"
        case .digitalServices: return "Цифровые сервисы"
        case .subscriptions: return "Подписки"
        case .insurance: return "Страхование"
        case .homeRepair: return "Ремонт дома"
        case .flowersGifts: return "Цветы и подарки"
        case .alcohol: return "Алкомаркеты"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .gasStation: return "⛽️"
        case .supermarket: return "🛒"
        case .restaurant: return "🍽️"
        case .fastFood: return "🍔"
        case .coffeeShop: return "☕️"
        case .pharmacy: return "💊"
        case .healthcare: return "🩺"
        case .transport: return "🚕"
        case .taxi: return "🚖"
        case .carSharing: return "🚗"
        case .autoServices: return "🛠️"
        case .entertainment: return "🎮"
        case .cinema: return "🎬"
        case .travel: return "🧳"
        case .hotels: return "🏨"
        case .airlines: return "✈️"
        case .railway: return "🚆"
        case .online: return "🌐"
        case .marketplaces: return "📦"
        case .electronics: return "💻"
        case .homeGoods: return "🏠"
        case .furniture: return "🛋️"
        case .clothing: return "👕"
        case .shoes: return "👟"
        case .beauty: return "💄"
        case .sport: return "🏋️"
        case .books: return "📚"
        case .education: return "🎓"
        case .kids: return "🧸"
        case .pets: return "🐾"
        case .telecom: return "📱"
        case .internet: return "📶"
        case .utilities: return "💡"
        case .digitalServices: return "🖥️"
        case .subscriptions: return "🔁"
        case .insurance: return "🛡️"
        case .homeRepair: return "🔧"
        case .flowersGifts: return "🎁"
        case .alcohol: return "🍷"
        case .other: return "🧩"
        }
    }
}

/// Пользовательская категория кешбэка
@Model
final class CashbackCustomCategory: Persistable {
    static let defaultIcon = "🛒"
    static let allowedSFSymbolIcons: [String] = [
        "tag.fill",
        "cart.fill",
        "fuelpump.fill",
        "fork.knife",
        "cross.case.fill",
        "car.fill",
        "gamecontroller.fill",
        "globe",
        "house.fill",
        "figure.walk",
        "cup.and.saucer.fill",
        "gift.fill",
        "airplane",
        "iphone",
        "bolt.fill",
        "heart.fill",
        "basket.fill",
        "takeoutbag.and.cup.and.straw.fill",
        "wineglass.fill",
        "fork.knife.circle.fill",
        "birthday.cake.fill",
        "popcorn.fill",
        "ticket.fill",
        "film.fill",
        "tv.fill",
        "music.note",
        "music.mic",
        "headphones",
        "book.fill",
        "graduationcap.fill",
        "gamecontroller",
        "soccerball",
        "dumbbell.fill",
        "figure.run",
        "tent.fill",
        "beach.umbrella.fill",
        "mountain.2.fill",
        "camera.fill",
        "photo.fill",
        "paintpalette.fill",
        "theatermasks.fill",
        "stethoscope",
        "pills.fill",
        "bandage.fill",
        "cross.vial.fill",
        "pawprint.fill",
        "dog.fill",
        "cat.fill",
        "leaf.fill",
        "tree.fill",
        "car.2.fill",
        "bus.fill",
        "tram.fill",
        "ferry.fill",
        "bicycle",
        "scooter",
        "airplane.departure",
        "bed.double.fill",
        "shippingbox.fill",
        "cube.box.fill",
        "bag.fill",
        "creditcard.fill",
        "banknote.fill",
        "building.columns.fill",
        "dollarsign.circle.fill",
        "eurosign.circle.fill",
        "rublesign.circle.fill",
        "chart.line.uptrend.xyaxis",
        "briefcase.fill",
        "building.2.fill",
        "desktopcomputer",
        "laptopcomputer",
        "display",
        "keyboard.fill",
        "printer.fill",
        "wifi",
        "antenna.radiowaves.left.and.right",
        "phone.fill",
        "message.fill",
        "envelope.fill",
        "doc.text.fill",
        "newspaper.fill",
        "calendar",
        "clock.fill",
        "sparkles",
        "sun.max.fill",
        "moon.fill",
        "cloud.fill",
        "umbrella.fill",
        "snowflake",
        "flame.fill",
        "drop.fill",
        "bolt.circle.fill",
        "shield.fill",
        "lock.fill",
        "person.fill",
        "person.2.fill",
        "person.3.fill",
        "child.fill",
        "figure.2.and.child.holdinghands",
        "house.lodge.fill",
        "key.fill",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "scissors",
        "sewingneedle",
        "basketball.fill",
        "volleyball.fill",
        "baseball.fill",
        "trophy.fill",
        "medal.fill",
        "flag.checkered",
        "location.fill",
        "map.fill",
        "signpost.right.fill",
        "carrot.fill",
        "fish.fill",
        "takeoutbag.and.cup.and.straw",
        "cup.and.heat.waves.fill",
        "lanyardcard.fill",
        "comb.fill",
        "facemask.fill"
    ]
    static let allowedEmojiIcons: [String] = [
        "🛒", "🛍️", "🏪", "🏬", "🧺", "🍽️", "🍔", "🍕", "🍣", "🍜",
        "☕️", "🍰", "🍩", "🍿", "🎬", "🎮", "🎯", "🎟️", "🎨", "🎵",
        "🎧", "📚", "🧠", "💊", "🩺", "🏥", "🚕", "🚗", "🚌", "🚇",
        "🚲", "🛴", "⛽️", "✈️", "🏨", "🧳", "💼", "🖥️", "💻", "📱",
        "⌚️", "📞", "📶", "🌐", "🛜", "🔌", "💡", "🏠", "🔑", "🛠️",
        "🧰", "🧹", "🧴", "👕", "👟", "💄", "💇", "💆", "🧸",
        "🍼", "🐶", "🐱", "🐾", "🌿", "🌸", "🌳", "🔥", "💧", "☀️",
        "🌙", "🌧️", "❄️", "⚡️", "🧾", "📰", "📦", "🚚", "💳", "💰",
        "🪙", "🏦", "📈", "📊", "🧯", "🛡️", "🔒", "❤️", "🧡", "💜",
        "⭐️", "✨", "🎁", "🏆", "🏅", "⚽️", "🏀", "🏋️", "🧘", "🧑‍💻"
    ]
    static let allowedIcons: [String] = allowedSFSymbolIcons + allowedEmojiIcons

    /// Уникальный идентификатор категории
    var categoryID: String = UUID().uuidString

    /// Отображаемое имя
    var name: String = ""

    /// Нормализованное имя для дедупликации
    var normalizedName: String = ""

    /// Иконка категории (SF Symbol или emoji)
    var icon: String = defaultIcon

    /// Дата создания
    var createdAt: Date = Date()

    /// Дата обновления
    var updatedAt: Date = Date()

    init(name: String, icon: String = CashbackCustomCategory.defaultIcon) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.categoryID = UUID().uuidString
        self.name = trimmed
        self.normalizedName = CashbackCustomCategory.normalize(trimmed)
        self.icon = CashbackCustomCategory.normalizeIcon(icon)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizeIcon(_ icon: String) -> String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowedIcons.contains(trimmed) ? trimmed : defaultIcon
    }

    static func isSFSymbolIcon(_ icon: String) -> Bool {
        allowedSFSymbolIcons.contains(icon)
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "CashbackCustomCategory",
            "categoryID": categoryID,
            "name": name,
            "normalizedName": normalizedName,
            "icon": icon,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["categoryID"] as? String != nil,
              dict["name"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}

/// Унифицированная категория для UI (системная или пользовательская)
struct CashbackCategoryOption: Identifiable, Hashable {
    /// Стабильный raw-ключ для хранения в Cashback.categoryRaw
    let rawValue: String
    let displayName: String
    let icon: String
    let isCustom: Bool

    var id: String { rawValue }
}

/// Кешбэк
@Model
final class Cashback: Persistable {
    static let customCategoryPrefix = "custom:"

    /// Название кешбэка
    var name: String = ""
    
    /// Категория кешбэка
    var categoryRaw: String = "other"
    
    /// Процент кешбэка (0.0 - 100.0)
    var percentage: Double = 0.0

    /// Месяц действия кешбэка в формате yyyy-MM
    var monthKey: String = Cashback.monthKey(for: Date())
    
    /// ID привязанных карт - массив для поддержки нескольких карт
    var cardIDs: [String] = []
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    var category: CashbackCategory {
        get { CashbackCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Категория является пользовательской
    var isCustomCategory: Bool {
        categoryRaw.hasPrefix(Self.customCategoryPrefix)
    }

    /// Отображаемое имя категории (системное или пользовательское)
    var displayCategoryName: String {
        if let systemCategory = CashbackCategory(rawValue: categoryRaw) {
            return systemCategory.displayName
        }
        if isCustomCategory, !name.isEmpty {
            return name
        }
        return CashbackCategory.other.displayName
    }

    /// Отображаемая иконка категории (для неизвестной категории используем fallback "Другое")
    var displayCategoryIcon: String {
        CashbackCategory(rawValue: categoryRaw)?.icon ?? CashbackCategory.other.icon
    }
    
    /// Форматированный процент для отображения
    var formattedPercentage: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: percentage)) ?? "0")%"
    }
    
    init(
        name: String,
        category: CashbackCategory = .other,
        percentage: Double = 0.0,
        cardIDs: [String] = [],
        monthKey: String = Cashback.monthKey(for: Date())
    ) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.percentage = percentage
        self.cardIDs = cardIDs
        self.monthKey = monthKey
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(
        name: String,
        categoryRaw: String,
        percentage: Double = 0.0,
        cardIDs: [String] = [],
        monthKey: String = Cashback.monthKey(for: Date())
    ) {
        self.name = name
        self.categoryRaw = categoryRaw
        self.percentage = percentage
        self.cardIDs = cardIDs
        self.monthKey = monthKey
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 1970
        let month = comps.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }

    static func startOfMonth(for monthKey: String, calendar: Calendar = .current) -> Date? {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }
    
    // MARK: - Exportable
    
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "Cashback",
            "name": name,
            "categoryRaw": categoryRaw,
            "percentage": percentage,
            "cardIDs": cardIDs,
            "monthKey": monthKey,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["name"] as? String != nil,
              dict["categoryRaw"] as? String != nil,
              dict["percentage"] as? Double != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
}
