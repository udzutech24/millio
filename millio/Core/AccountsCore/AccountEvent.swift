import Foundation
import SwiftData

/// Единственная сущность операции по счёту (event-sourcing). Любое изменение баланса —
/// это вставка AccountEvent, никогда прямая мутация числового поля (AC1, AC9).
@Model
final class AccountEvent {
    // Без @Attribute(.unique) — см. комментарий в Account.swift (CloudKit-конфигурация не поддерживает unique).
    var id: UUID = UUID()

    var account: Account?

    /// Дата операции (может быть в будущем — используется для реплея-прогноза вклада/кредита).
    var date: Date = Date()
    /// Момент создания записи — второй ключ сортировки при совпадении `date` (детерминизм, S5).
    var createdAt: Date = Date()
    /// Локальный календарный день на МОМЕНТ СОЗДАНИЯ (риск Т5: смена таймзоны пользователя
    /// не должна задним числом переносить операцию в другой день). Формат "yyyy-MM-dd".
    var dayKey: String = ""

    var typeRaw: String = AccountEventType.adjustment.rawValue

    /// Сумма в валюте события (income/expense/interest/fee/adjustment-дельта и т.п.).
    var amount: Decimal?
    /// Количество актива (buy/sell для рыночных счетов).
    var quantity: Decimal?
    /// Цена за единицу на момент события (buy/sell/revaluation).
    var unitPrice: Decimal?
    /// Зафиксированный курс к базовой валюте на момент события (append-only, AC10).
    var fxRateToBase: Decimal?
    /// true — курс временный (нет опубликованного курса на дату, П.С6), подлежит замене при появлении официального.
    var fxProvisional: Bool = false

    var categoryID: String?
    var note: String?

    /// Связывает две ноги перевода между счетами (AC12: Σ переводов = 0).
    var transferID: UUID?

    /// Если оплата была в другой валюте, чем валюта счёта — оригинальная сумма/валюта (для отображения).
    var originalAmount: Decimal?
    var originalCurrency: String?

    /// Курс редоминации (старая валюта → новая), только для type == .redenomination. Не пересчитывается задним числом (AC11/AC15).
    var redenomRate: Decimal?
    var redenomFromCurrency: String?

    var type: AccountEventType {
        get { AccountEventType(rawValue: typeRaw) ?? .adjustment }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        account: Account? = nil,
        date: Date,
        createdAt: Date = Date(),
        type: AccountEventType,
        amount: Decimal? = nil,
        quantity: Decimal? = nil,
        unitPrice: Decimal? = nil,
        fxRateToBase: Decimal? = nil,
        fxProvisional: Bool = false,
        categoryID: String? = nil,
        note: String? = nil,
        transferID: UUID? = nil,
        originalAmount: Decimal? = nil,
        originalCurrency: String? = nil,
        redenomRate: Decimal? = nil,
        redenomFromCurrency: String? = nil
    ) {
        self.id = id
        self.account = account
        self.date = date
        self.createdAt = createdAt
        self.dayKey = Self.makeDayKey(from: date)
        self.typeRaw = type.rawValue
        self.amount = amount
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.fxRateToBase = fxRateToBase
        self.fxProvisional = fxProvisional
        self.categoryID = categoryID
        self.note = note
        self.transferID = transferID
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.redenomRate = redenomRate
        self.redenomFromCurrency = redenomFromCurrency
    }

    private static func makeDayKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
