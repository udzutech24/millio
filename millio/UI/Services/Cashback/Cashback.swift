//
//  Cashback.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Категория кешбэка
enum CashbackCategory: String, Codable, CaseIterable {
    case gasStation = "gas_station"
    case supermarket = "supermarket"
    case restaurant = "restaurant"
    case pharmacy = "pharmacy"
    case transport = "transport"
    case entertainment = "entertainment"
    case online = "online"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .gasStation: return "Заправки"
        case .supermarket: return "Супермаркеты"
        case .restaurant: return "Рестораны"
        case .pharmacy: return "Аптеки"
        case .transport: return "Транспорт"
        case .entertainment: return "Развлечения"
        case .online: return "Онлайн"
        case .other: return "Другое"
        }
    }
    
    var icon: String {
        switch self {
        case .gasStation: return "⛽️"
        case .supermarket: return "🛒"
        case .restaurant: return "🍽️"
        case .pharmacy: return "💊"
        case .transport: return "🚕"
        case .entertainment: return "🎮"
        case .online: return "🌐"
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
