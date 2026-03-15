//
//  CashflowTransaction.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

// MARK: - Transaction Type

enum CashflowTransactionType: String, Codable, CaseIterable {
    case income = "income"      // Доход
    case expense = "expense"    // Расход
    case transfer = "transfer"  // Перевод
    case balanceAdjustment = "balance_adjustment"  // Ручное изменение баланса
    case cardBalanceAdjustment = "card_balance_adjustment" // Корректировка баланса карты
    case creditDebtAdjustment = "credit_debt_adjustment"   // Корректировка долга

    static var allCases: [CashflowTransactionType] {
        // Пользовательские типы для ручного создания операций
        [.income, .expense, .transfer]
    }

    var displayName: String {
        switch self {
        case .income: return String(localized: "Income")
        case .expense: return String(localized: "Expense")
        case .transfer: return String(localized: "Transfer")
        case .balanceAdjustment: return String(localized: "Asset value adjustment")
        case .cardBalanceAdjustment: return String(localized: "Account balance adjustment")
        case .creditDebtAdjustment: return String(localized: "Debt adjustment")
        }
    }
    
    var icon: String {
        switch self {
        case .income: return "arrow.down.circle.fill"
        case .expense: return "arrow.up.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        case .balanceAdjustment: return "pencil.circle.fill"
        case .cardBalanceAdjustment: return "creditcard.circle.fill"
        case .creditDebtAdjustment: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Recurrence Rule

enum CashflowRecurrenceRule: String, Codable, CaseIterable {
    case none = "none"
    case weekly = "weekly"
    case monthly = "monthly"
    case quarterly = "quarterly"
    case semiannual = "semiannual"
    case yearly = "yearly"

    var displayName: String {
        switch self {
        case .none: return String(localized: "Do not repeat")
        case .weekly:
            if Locale.autoupdatingCurrent.identifier.lowercased().hasPrefix("ru") {
                return "Еженедельно"
            }
            return "Weekly"
        case .monthly: return String(localized: "Monthly")
        case .quarterly:
            return String(
                localized: "cashflow.recurrence.quarterly",
                defaultValue: "Every 3 months",
                comment: "Quarterly recurrence rule label"
            )
        case .semiannual:
            return String(
                localized: "cashflow.recurrence.semiannual",
                defaultValue: "Every 6 months",
                comment: "Semiannual recurrence rule label"
            )
        case .yearly:
            return String(
                localized: "cashflow.recurrence.yearly",
                defaultValue: "Every year",
                comment: "Yearly recurrence rule label"
            )
        }
    }

    var monthInterval: Int? {
        switch self {
        case .none:
            return nil
        case .weekly:
            return nil
        case .monthly:
            return 1
        case .quarterly:
            return 3
        case .semiannual:
            return 6
        case .yearly:
            return 12
        }
    }
}

enum CashflowRecurrenceWeekday: Int, Codable, CaseIterable, Hashable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var shortDisplayName: String {
        let symbols = DateFormatter().veryShortStandaloneWeekdaySymbols ?? DateFormatter().shortWeekdaySymbols
        let index = rawValue - 1
        guard let symbols, symbols.indices.contains(index) else {
            return "\(rawValue)"
        }
        return symbols[index]
    }

    static func from(calendarWeekday value: Int) -> CashflowRecurrenceWeekday? {
        Self(rawValue: value)
    }

    static func orderedForCurrentLocale(calendar: Calendar = .autoupdatingCurrent) -> [CashflowRecurrenceWeekday] {
        let first = max(1, min(calendar.firstWeekday, 7))
        let orderedRaw = (0..<7).map { offset in
            ((first - 1 + offset) % 7) + 1
        }
        return orderedRaw.compactMap(CashflowRecurrenceWeekday.init(rawValue:))
    }
}

// MARK: - Income Category

enum IncomeCategory: String, Codable, CaseIterable {
    case salary = "salary"           // Зарплата
    case freelance = "freelance"     // Фриланс
    case business = "business"       // Бизнес
    case bonus = "bonus"             // Премия
    case investment = "investment"   // Инвестиции
    case rental = "rental"           // Аренда
    case gift = "gift"               // Подарок
    case other = "other"             // Другое
    
    var displayName: String {
        switch self {
        case .salary: return String(localized: "Salary")
        case .freelance: return String(localized: "Freelance")
        case .business: return String(localized: "Business")
        case .investment: return String(localized: "Investments")
        case .rental: return String(localized: "Rental")
        case .gift: return String(localized: "Gift")
        case .bonus: return String(localized: "Bonus")
        case .other: return String(localized: "Other")
        }
    }
    
    var icon: String {
        switch self {
        case .salary: return "💳"
        case .freelance: return "🛠️"
        case .business: return "🏢"
        case .bonus: return "🏅"
        case .investment: return "📈"
        case .rental: return "🏘️"
        case .gift: return "🎁"
        case .other: return "📦"
        }
    }
}

// MARK: - Expense Category

enum ExpenseCategory: String, Codable, CaseIterable {
    case groceries = "groceries"     // Продукты
    case cafe = "cafe"               // Кафе
    case fastFood = "fast_food"      // Фастфуд
    case coffeeShops = "coffee_shops" // Кофейни
    case transport = "transport"     // Транспорт
    case taxi = "taxi"               // Такси
    case fuel = "fuel"               // Топливо и АЗС
    case carService = "car_service"  // Автосервис
    case shopping = "shopping"       // Покупки
    case marketplaces = "marketplaces" // Маркетплейсы
    case clothing = "clothing"       // Одежда и обувь
    case homeGoods = "home_goods"    // Товары для дома
    case entertainment = "entertainment" // Развлечения
    case bills = "bills"             // Счета
    case telecom = "telecom"         // Связь и интернет
    case utilities = "utilities"     // Коммунальные
    case health = "health"           // Здоровье
    case pharmacies = "pharmacies"   // Аптеки
    case medicalServices = "medical_services" // Медицинские услуги
    case beauty = "beauty"           // Красота и уход
    case education = "education"     // Образование
    case travel = "travel"           // Путешествия
    case digitalServices = "digital_services" // Цифровые сервисы
    case subscriptions = "subscriptions" // Подписки
    case pets = "pets"               // Животные
    case transfers = "transfers"     // Переводы
    case other = "other"             // Другое
    
    var displayName: String {
        ExpenseCategoryCatalog.metadata(for: self).localizedDisplayName()
    }
    
    var icon: String {
        ExpenseCategoryCatalog.metadata(for: self).icon
    }
}

// MARK: - Custom Category

enum CashflowCategoryKind: String, Codable, CaseIterable {
    case income = "income"
    case expense = "expense"
}

struct CashflowAssetChangeSnapshot {
    let quantity: Double?
    let unitPrice: Double?
    let totalAmount: Double
}

@Model
final class CashflowSystemCategoryOverride: Persistable {
    var overrideID: String = UUID().uuidString
    var kindRaw: String = CashflowCategoryKind.expense.rawValue
    var categoryRaw: String = ""
    var name: String = ""
    var normalizedName: String = ""
    var icon: String = CashflowCustomCategory.defaultIcon
    var isHidden: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: CashflowCategoryKind {
        get { CashflowCategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    init(
        kind: CashflowCategoryKind,
        categoryRaw: String,
        name: String,
        icon: String,
        isHidden: Bool = false
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.overrideID = UUID().uuidString
        self.kindRaw = kind.rawValue
        self.categoryRaw = categoryRaw
        self.name = trimmedName
        self.normalizedName = CashflowCustomCategory.normalize(trimmedName)
        self.icon = CashflowCustomCategory.normalizeIcon(icon)
        self.isHidden = isHidden
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "CashflowSystemCategoryOverride",
            "overrideID": overrideID,
            "kindRaw": kindRaw,
            "categoryRaw": categoryRaw,
            "name": name,
            "normalizedName": normalizedName,
            "icon": icon,
            "isHidden": isHidden,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["overrideID"] as? String != nil,
              dict["kindRaw"] as? String != nil,
              dict["categoryRaw"] as? String != nil,
              dict["name"] as? String != nil,
              dict["icon"] as? String != nil,
              dict["isHidden"] as? Bool != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}

@Model
final class CashflowCustomCategory: Persistable {
    static let defaultIcon = "🧩"
    static let allowedSFSymbolIcons: [String] = [
        "tag.fill",
        "cart.fill",
        "cup.and.saucer.fill",
        "fuelpump.fill",
        "fork.knife",
        "cross.case.fill",
        "car.fill",
        "gamecontroller.fill",
        "globe",
        "house.fill",
        "figure.walk",
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

    static func isSFSymbolIcon(_ icon: String) -> Bool {
        allowedSFSymbolIcons.contains(icon)
    }

    static func normalizeIcon(_ icon: String) -> String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowedIcons.contains(trimmed) ? trimmed : defaultIcon
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var categoryID: String = UUID().uuidString
    var kindRaw: String = CashflowCategoryKind.expense.rawValue
    var name: String = ""
    var normalizedName: String = ""
    var icon: String = defaultIcon
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var kind: CashflowCategoryKind {
        get { CashflowCategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    init(
        kind: CashflowCategoryKind,
        name: String,
        icon: String = CashflowCustomCategory.defaultIcon
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.categoryID = UUID().uuidString
        self.kindRaw = kind.rawValue
        self.name = trimmed
        self.normalizedName = Self.normalize(trimmed)
        self.icon = Self.normalizeIcon(icon)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "CashflowCustomCategory",
            "categoryID": categoryID,
            "kindRaw": kindRaw,
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
              dict["kindRaw"] as? String != nil,
              dict["name"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}

struct CashflowCategoryOption: Identifiable, Hashable {
    let rawValue: String
    let displayName: String
    let icon: String
    let isCustom: Bool

    var id: String { rawValue }
}

// MARK: - Cashflow Transaction

@Model
final class CashflowTransaction: Persistable {
    static let customCategoryPrefix = "custom:"

    /// Тип транзакции
    var transactionTypeRaw: String = "expense"
    
    /// Категория дохода (если тип = income)
    var incomeCategoryRaw: String?
    
    /// Категория расхода (если тип = expense)
    var expenseCategoryRaw: String?
    
    /// Сумма транзакции
    var amount: Double = 0.0
    
    /// Валюта
    var currency: String = "RUB"

    /// Зафиксированный курс для истории (transaction.currency -> exchangeRateCurrency)
    var exchangeRate: Double?

    /// Дата курса (дневная гранулярность)
    var exchangeRateDate: Date?

    /// Валюта, к которой применяется exchangeRate
    var exchangeRateCurrency: String?
    
    /// Дата транзакции
    var transactionDate: Date = Date()
    
    /// ID карты для дохода/расхода (или карты-источника для перевода)
    var cardID: String?
    
    /// ID карты-получателя для перевода
    var toCardID: String?
    
    /// ID кредита (для транзакций связанных с кредитами)
    var creditID: String?
    
    /// ID инвестиции (для транзакций связанных с инвестициями)
    var investmentID: String?
    
    /// Описание/комментарий
    var note: String?

    /// Снимок количества актива до изменения.
    var assetQuantityBefore: Double?

    /// Снимок количества актива после изменения.
    var assetQuantityAfter: Double?

    /// Снимок цены одной единицы актива до изменения.
    var assetUnitPriceBefore: Double?

    /// Снимок цены одной единицы актива после изменения.
    var assetUnitPriceAfter: Double?

    /// Снимок полной стоимости актива до изменения.
    var assetAmountBefore: Double?

    /// Снимок полной стоимости актива после изменения.
    var assetAmountAfter: Double?

    /// Источник пакетного импорта для идемпотентного обновления импортных наборов.
    var importSourceRaw: String?

    /// Уникальный ключ импортной записи внутри её источника.
    var importReferenceKey: String?

    /// Правило автоповтора (none/weekly/monthly/legacy)
    var recurrenceRuleRaw: String = CashflowRecurrenceRule.none.rawValue

    /// Дни недели для weekly-повтора. Формат: "2,4,6" (понедельник/среда/пятница)
    var recurrenceWeekdaysRaw: String?

    /// ID серии автоповтора (общий для всех операций серии)
    var recurrenceSeriesID: String?

    /// Влияет ли операция на текущий остаток карты
    var affectsCardBalance: Bool = true

    /// Был ли эффект операции уже применен к текущему балансу счета.
    /// Нужен, чтобы не применять одну и ту же операцию повторно при reopen/auto-apply.
    var hasAppliedBalanceEffect: Bool = false
    
    /// Дата создания записи
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()
    
    var transactionType: CashflowTransactionType {
        get { CashflowTransactionType(rawValue: transactionTypeRaw) ?? .expense }
        set { transactionTypeRaw = newValue.rawValue }
    }
    
    var incomeCategory: IncomeCategory? {
        get {
            guard let raw = incomeCategoryRaw else { return nil }
            return IncomeCategory(rawValue: raw)
        }
        set { incomeCategoryRaw = newValue?.rawValue }
    }
    
    var expenseCategory: ExpenseCategory? {
        get {
            guard let raw = expenseCategoryRaw else { return nil }
            return ExpenseCategory(rawValue: raw)
        }
        set { expenseCategoryRaw = newValue?.rawValue }
    }

    var recurrenceRule: CashflowRecurrenceRule {
        get { CashflowRecurrenceRule(rawValue: recurrenceRuleRaw) ?? .none }
        set { recurrenceRuleRaw = newValue.rawValue }
    }

    var recurrenceWeekdays: Set<CashflowRecurrenceWeekday> {
        get {
            guard let recurrenceWeekdaysRaw,
                  !recurrenceWeekdaysRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            let values = recurrenceWeekdaysRaw
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .compactMap(CashflowRecurrenceWeekday.init(rawValue:))
            return Set(values)
        }
        set {
            let values = newValue.map(\.rawValue).sorted()
            recurrenceWeekdaysRaw = values.isEmpty ? nil : values.map(String.init).joined(separator: ",")
        }
    }

    var isRecurringTemplate: Bool {
        recurrenceRule != .none
        && (transactionType == .income || transactionType == .expense)
        && recurrenceSeriesID != nil
    }

    var hasAssetChangeSnapshot: Bool {
        assetQuantityBefore != nil
            || assetQuantityAfter != nil
            || assetUnitPriceBefore != nil
            || assetUnitPriceAfter != nil
            || assetAmountBefore != nil
            || assetAmountAfter != nil
    }
    
    init(
        transactionType: CashflowTransactionType,
        amount: Double,
        currency: String,
        transactionDate: Date,
        cardID: String? = nil,
        toCardID: String? = nil,
        creditID: String? = nil,
        investmentID: String? = nil,
        incomeCategory: IncomeCategory? = nil,
        expenseCategory: ExpenseCategory? = nil,
        incomeCategoryRaw: String? = nil,
        expenseCategoryRaw: String? = nil,
        note: String? = nil,
        importSourceRaw: String? = nil,
        importReferenceKey: String? = nil,
        recurrenceRule: CashflowRecurrenceRule = .none,
        recurrenceWeekdays: Set<CashflowRecurrenceWeekday> = [],
        recurrenceSeriesID: String? = nil,
        affectsCardBalance: Bool = true
    ) {
        self.transactionTypeRaw = transactionType.rawValue
        self.amount = amount
        self.currency = currency
        self.transactionDate = transactionDate
        self.cardID = cardID
        self.toCardID = toCardID
        self.creditID = creditID
        self.investmentID = investmentID
        self.incomeCategoryRaw = incomeCategoryRaw ?? incomeCategory?.rawValue
        self.expenseCategoryRaw = expenseCategoryRaw ?? expenseCategory?.rawValue
        self.note = note
        self.importSourceRaw = importSourceRaw
        self.importReferenceKey = importReferenceKey
        self.recurrenceRuleRaw = recurrenceRule.rawValue
        self.recurrenceWeekdays = recurrenceWeekdays
        self.recurrenceSeriesID = recurrenceSeriesID
        self.affectsCardBalance = affectsCardBalance
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    var transactionUniqueID: String {
        "\(transactionTypeRaw)|\(transactionDate.timeIntervalSince1970)|\(amount)|\(createdAt.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "CashflowTransaction",
            "transactionTypeRaw": transactionTypeRaw,
            "amount": amount,
            "currency": currency,
            "transactionDate": transactionDate.timeIntervalSince1970,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "transactionUniqueID": transactionUniqueID
        ]
        
        if let incomeCategoryRaw = incomeCategoryRaw {
            dict["incomeCategoryRaw"] = incomeCategoryRaw
        }
        if let expenseCategoryRaw = expenseCategoryRaw {
            dict["expenseCategoryRaw"] = expenseCategoryRaw
        }
        if let cardID = cardID {
            dict["cardID"] = cardID
        }
        if let toCardID = toCardID {
            dict["toCardID"] = toCardID
        }
        if let creditID = creditID {
            dict["creditID"] = creditID
        }
        if let investmentID = investmentID {
            dict["investmentID"] = investmentID
        }
        if let note = note {
            dict["note"] = note
        }
        if let assetQuantityBefore = assetQuantityBefore {
            dict["assetQuantityBefore"] = assetQuantityBefore
        }
        if let assetQuantityAfter = assetQuantityAfter {
            dict["assetQuantityAfter"] = assetQuantityAfter
        }
        if let assetUnitPriceBefore = assetUnitPriceBefore {
            dict["assetUnitPriceBefore"] = assetUnitPriceBefore
        }
        if let assetUnitPriceAfter = assetUnitPriceAfter {
            dict["assetUnitPriceAfter"] = assetUnitPriceAfter
        }
        if let assetAmountBefore = assetAmountBefore {
            dict["assetAmountBefore"] = assetAmountBefore
        }
        if let assetAmountAfter = assetAmountAfter {
            dict["assetAmountAfter"] = assetAmountAfter
        }
        if let importSourceRaw = importSourceRaw {
            dict["importSourceRaw"] = importSourceRaw
        }
        if let importReferenceKey = importReferenceKey {
            dict["importReferenceKey"] = importReferenceKey
        }
        if let exchangeRate = exchangeRate {
            dict["exchangeRate"] = exchangeRate
        }
        if let exchangeRateDate = exchangeRateDate {
            dict["exchangeRateDate"] = exchangeRateDate.timeIntervalSince1970
        }
        if let exchangeRateCurrency = exchangeRateCurrency {
            dict["exchangeRateCurrency"] = exchangeRateCurrency
        }
        if recurrenceRule != .none {
            dict["recurrenceRuleRaw"] = recurrenceRuleRaw
        }
        if let recurrenceWeekdaysRaw, recurrenceRule == .weekly {
            dict["recurrenceWeekdaysRaw"] = recurrenceWeekdaysRaw
        }
        if let recurrenceSeriesID = recurrenceSeriesID {
            dict["recurrenceSeriesID"] = recurrenceSeriesID
        }
        if !affectsCardBalance {
            dict["affectsCardBalance"] = false
        }
        if hasAppliedBalanceEffect {
            dict["hasAppliedBalanceEffect"] = true
        }
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "CashflowTransaction"
    }

    func applyAssetChangeSnapshot(
        before: CashflowAssetChangeSnapshot,
        after: CashflowAssetChangeSnapshot
    ) {
        assetQuantityBefore = before.quantity
        assetQuantityAfter = after.quantity
        assetUnitPriceBefore = before.unitPrice
        assetUnitPriceAfter = after.unitPrice
        assetAmountBefore = before.totalAmount
        assetAmountAfter = after.totalAmount
    }
}
