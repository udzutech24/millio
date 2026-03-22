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
    case interest = "interest"       // Проценты
    case dividends = "dividends"     // Дивиденды
    case rental = "rental"           // Аренда
    case sale = "sale"               // Продажа вещей
    case refunds = "refunds"         // Возвраты
    case gift = "gift"               // Подарок
    case other = "other"             // Другое

    // Legacy system category kept for backward compatibility with saved data and notes.
    case investment = "investment"   // Инвестиции

    static var allCases: [IncomeCategory] {
        [
            .salary,
            .freelance,
            .business,
            .bonus,
            .interest,
            .dividends,
            .rental,
            .sale,
            .refunds,
            .gift,
            .other
        ]
    }
    
    var displayName: String {
        localizedDisplayName()
    }

    func localizedDisplayName(locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case .salary: return localizedName(locale: locale, ru: "Зарплата", en: "Salary")
        case .freelance: return localizedName(locale: locale, ru: "Фриланс", en: "Freelance")
        case .business: return localizedName(locale: locale, ru: "Бизнес", en: "Business")
        case .bonus: return localizedName(locale: locale, ru: "Премия", en: "Bonus")
        case .interest: return localizedName(locale: locale, ru: "Проценты", en: "Interest")
        case .dividends: return localizedName(locale: locale, ru: "Дивиденды", en: "Dividends")
        case .rental: return localizedName(locale: locale, ru: "Аренда", en: "Rental")
        case .sale: return localizedName(locale: locale, ru: "Продажа вещей", en: "Sale")
        case .refunds: return localizedName(locale: locale, ru: "Возвраты", en: "Refunds")
        case .gift: return localizedName(locale: locale, ru: "Подарок", en: "Gift")
        case .other: return localizedName(locale: locale, ru: "Другое", en: "Other")
        case .investment: return localizedName(locale: locale, ru: "Инвестиции", en: "Investments")
        }
    }

    static func matchesSearch(rawValue: String, query: String, locale: Locale = .autoupdatingCurrent) -> Bool {
        let normalizedQuery = normalizeSearchQuery(query)
        guard !normalizedQuery.isEmpty else { return true }
        guard let category = IncomeCategory(rawValue: rawValue) else { return false }

        let candidates = [
            category.localizedDisplayName(locale: locale),
            category.localizedDisplayName(locale: Locale(identifier: "ru_RU")),
            category.localizedDisplayName(locale: Locale(identifier: "en_US")),
            rawValue
        ]

        return candidates
            .map(normalizeSearchQuery)
            .contains { candidate in
                candidate.contains(normalizedQuery) || normalizedQuery.contains(candidate)
            }
    }
    
    var icon: String {
        switch self {
        case .salary: return "💼"
        case .freelance: return "🛠️"
        case .business: return "🏢"
        case .bonus: return "🎉"
        case .interest: return "🏦"
        case .dividends: return "📈"
        case .rental: return "🏘️"
        case .sale: return "🏷️"
        case .refunds: return "↩️"
        case .gift: return "🎁"
        case .other: return "🧩"
        case .investment: return "📈"
        }
    }

    static func canonicalRawValue(_ rawValue: String) -> String {
        switch rawValue {
        case IncomeCategory.investment.rawValue:
            return IncomeCategory.dividends.rawValue
        default:
            return rawValue
        }
    }
}

// MARK: - Expense Category

enum ExpenseCategory: String, Codable, CaseIterable {
    case groceries = "groceries"     // Продукты
    case dining = "dining"           // Еда вне дома
    case transport = "transport"     // Транспорт
    case taxi = "taxi"               // Такси
    case fuel = "fuel"               // Топливо и АЗС
    case carService = "car_service"  // Автосервис
    case housing = "housing"         // Жилье
    case utilities = "utilities"     // Коммунальные
    case telecom = "telecom"         // Связь и интернет
    case health = "health"           // Здоровье
    case pharmacy = "pharmacy"       // Аптека
    case shopping = "shopping"       // Покупки
    case clothing = "clothing"       // Одежда и обувь
    case electronics = "electronics" // Электроника
    case homeGoods = "home_goods"    // Товары для дома
    case education = "education"     // Образование
    case entertainment = "entertainment" // Развлечения
    case travel = "travel"           // Путешествия
    case subscriptions = "subscriptions" // Подписки
    case pets = "pets"               // Животные
    case gifts = "gifts"             // Подарки
    case beauty = "beauty"           // Красота и уход
    case insurance = "insurance"     // Страхование
    case taxesFees = "taxes_fees"    // Налоги и комиссии
    case transfers = "transfers"     // Переводы
    case other = "other"             // Другое

    // Legacy system categories kept for backward compatibility with saved data.
    case cafe = "cafe"
    case fastFood = "fast_food"
    case coffeeShops = "coffee_shops"
    case marketplaces = "marketplaces"
    case bills = "bills"
    case pharmacies = "pharmacies"
    case medicalServices = "medical_services"
    case digitalServices = "digital_services"

    static var allCases: [ExpenseCategory] {
        [
            .groceries,
            .dining,
            .transport,
            .taxi,
            .fuel,
            .carService,
            .housing,
            .utilities,
            .telecom,
            .health,
            .pharmacy,
            .shopping,
            .clothing,
            .electronics,
            .homeGoods,
            .education,
            .entertainment,
            .travel,
            .subscriptions,
            .pets,
            .gifts,
            .beauty,
            .insurance,
            .taxesFees,
            .transfers,
            .other
        ]
    }
    
    var displayName: String {
        ExpenseCategoryCatalog.metadata(for: self).localizedDisplayName()
    }
    
    var icon: String {
        ExpenseCategoryCatalog.metadata(for: self).icon
    }

    static func canonicalRawValue(_ rawValue: String) -> String {
        switch rawValue {
        case ExpenseCategory.cafe.rawValue,
             ExpenseCategory.fastFood.rawValue,
             ExpenseCategory.coffeeShops.rawValue:
            return ExpenseCategory.dining.rawValue
        case ExpenseCategory.marketplaces.rawValue:
            return ExpenseCategory.shopping.rawValue
        case ExpenseCategory.bills.rawValue:
            return ExpenseCategory.housing.rawValue
        case ExpenseCategory.pharmacies.rawValue:
            return ExpenseCategory.pharmacy.rawValue
        case ExpenseCategory.medicalServices.rawValue:
            return ExpenseCategory.health.rawValue
        case ExpenseCategory.digitalServices.rawValue:
            return ExpenseCategory.subscriptions.rawValue
        default:
            return rawValue
        }
    }
}

private func normalizeSearchQuery(_ value: String) -> String {
    value
        .lowercased()
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: "ё", with: "е")
        .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func localizedName(locale: Locale, ru: String, en: String) -> String {
    AppLocalization.string(en, locale: locale, fallback: ExpenseCategoryCatalog.preferredLanguageCode(for: locale) == "ru" ? ru : en)
}

// MARK: - Custom Category

enum CashflowCategoryKind: String, Codable, CaseIterable {
    case income = "income"
    case expense = "expense"
}

struct CashflowAssetChangeSnapshot {
    let quantity: Double?
    let unitPrice: Double?
    let purchaseUnitPrice: Double?
    let purchaseCost: Double?
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
        "wallet.pass.fill",
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

    /// ID составной операции, объединяющий технические legs одной сделки.
    var operationGroupID: String?
    
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

    /// Снимок средней цены покупки до изменения.
    var assetPurchaseUnitPriceBefore: Double?

    /// Снимок средней цены покупки после изменения.
    var assetPurchaseUnitPriceAfter: Double?

    /// Снимок полной себестоимости до изменения.
    var assetPurchaseCostBefore: Double?

    /// Снимок полной себестоимости после изменения.
    var assetPurchaseCostAfter: Double?

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

    /// Явный override участия операции в доходах/расходах Cashflow.
    /// `nil` означает legacy-режим: участие выводится из типа операции и известных паттернов.
    var affectsCashflowTotals: Bool?

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

    /// Операция должна участвовать в метриках доходов/расходов Cashflow.
    /// Optional-флаг позволяет без миграции корректно скрыть legacy settlement-транзакции
    /// от market buy/sell, которые раньше сохранялись как обычные income/expense.
    var shouldAffectCashflowTotals: Bool {
        if let affectsCashflowTotals {
            return affectsCashflowTotals
        }
        return !isLegacyInvestmentTradeSettlement
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
        operationGroupID: String? = nil,
        importSourceRaw: String? = nil,
        importReferenceKey: String? = nil,
        recurrenceRule: CashflowRecurrenceRule = .none,
        recurrenceWeekdays: Set<CashflowRecurrenceWeekday> = [],
        recurrenceSeriesID: String? = nil,
        affectsCardBalance: Bool = true,
        affectsCashflowTotals: Bool? = nil
    ) {
        self.transactionTypeRaw = transactionType.rawValue
        self.amount = amount
        self.currency = currency
        self.transactionDate = transactionDate
        self.cardID = cardID
        self.toCardID = toCardID
        self.creditID = creditID
        self.investmentID = investmentID
        self.operationGroupID = operationGroupID
        self.incomeCategoryRaw = incomeCategoryRaw ?? incomeCategory?.rawValue
        self.expenseCategoryRaw = expenseCategoryRaw ?? expenseCategory?.rawValue
        self.note = note
        self.importSourceRaw = importSourceRaw
        self.importReferenceKey = importReferenceKey
        self.recurrenceRuleRaw = recurrenceRule.rawValue
        self.recurrenceWeekdays = recurrenceWeekdays
        self.recurrenceSeriesID = recurrenceSeriesID
        self.affectsCardBalance = affectsCardBalance
        self.affectsCashflowTotals = affectsCashflowTotals
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
        if let operationGroupID = operationGroupID {
            dict["operationGroupID"] = operationGroupID
        }
        if let affectsCashflowTotals {
            dict["affectsCashflowTotals"] = affectsCashflowTotals
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
        if let assetPurchaseUnitPriceBefore = assetPurchaseUnitPriceBefore {
            dict["assetPurchaseUnitPriceBefore"] = assetPurchaseUnitPriceBefore
        }
        if let assetPurchaseUnitPriceAfter = assetPurchaseUnitPriceAfter {
            dict["assetPurchaseUnitPriceAfter"] = assetPurchaseUnitPriceAfter
        }
        if let assetPurchaseCostBefore = assetPurchaseCostBefore {
            dict["assetPurchaseCostBefore"] = assetPurchaseCostBefore
        }
        if let assetPurchaseCostAfter = assetPurchaseCostAfter {
            dict["assetPurchaseCostAfter"] = assetPurchaseCostAfter
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
        assetPurchaseUnitPriceBefore = before.purchaseUnitPrice
        assetPurchaseUnitPriceAfter = after.purchaseUnitPrice
        assetPurchaseCostBefore = before.purchaseCost
        assetPurchaseCostAfter = after.purchaseCost
        assetAmountBefore = before.totalAmount
        assetAmountAfter = after.totalAmount
    }
}

private extension CashflowTransaction {
    var isLegacyInvestmentTradeSettlement: Bool {
        switch transactionType {
        case .expense:
            return expenseCategoryRaw == ExpenseCategory.other.rawValue
                && note == String(localized: "finances.transaction.note.investment_buy")
        case .income:
            return incomeCategoryRaw == IncomeCategory.investment.rawValue
                && note == String(localized: "finances.transaction.note.investment_sell")
        case .transfer, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return false
        }
    }
}
