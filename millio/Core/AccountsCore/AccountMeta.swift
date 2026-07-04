import Foundation

// MARK: - Метаданные по типам счетов
//
// Value-структуры (Codable), хранятся в Account как опциональные поля.
// Заполняется только та метаструктура, что соответствует kind счёта — остальные nil.

/// Метаданные карты/счёта/наличных.
struct CardMeta: Codable, Equatable {
    var bank: String?
    var last4: String?
    var creditLimit: Decimal?
    var statementDay: Int?
    var dueDay: Int?
    var minPayment: Decimal?
    var graceDays: Int?
    var overdraftLimit: Decimal?
}

/// Капитализация процентов по вкладу.
/// Префикс Account* — во избежание конфликта с `DepositCapitalization` в старом Investment.swift (то ядро не трогаем).
enum AccountDepositCapitalization: String, Codable, Hashable, CaseIterable {
    case none
    case monthly
    case quarterly
}

/// Метаданные вклада. `termEnd == nil` — накопительный счёт (тот же движок B, без срока, Фаза 3):
/// НЕ отдельный пресет-экран, а переключатель «без срока» в форме вклада.
struct DepositMeta: Codable, Equatable {
    /// Процент годовых, ЧИСЛОМ-ПРОЦЕНТОМ (12 = 12%), как и `LoanMeta.rate` — не доля.
    var rate: Decimal
    var capitalization: AccountDepositCapitalization
    var termEnd: Date?
    var payoutDay: Int?
    var allowsTopUp: Bool
    var allowsEarlyClose: Bool
    /// Доля УДЕРЖАНИЯ начисленных % при досрочном закрытии, 0…1 (0.5 = банк забирает 50% начисленного) —
    /// в отличие от `rate` это ДОЛЯ, не процент (решение брифинга Фазы 3, во избежание двойной конвенции).
    var earlyClosePenalty: Decimal?
    var remindEnd: Bool
    var autoRollover: Bool
}

/// Тип графика погашения кредита.
enum LoanScheduleType: String, Codable {
    case annuity
    case differentiated
}

/// Метаданные кредита.
struct LoanMeta: Codable, Equatable {
    var principal: Decimal
    var rate: Decimal
    var monthlyPayment: Decimal?
    var paymentDay: Int?
    var termEnd: Date?
    var scheduleType: LoanScheduleType
    var insurance: Decimal?
}

/// Направление долга — кто кому должен.
enum DebtDirection: String, Codable {
    case owedToMe
    case owedByMe
}

/// Метаданные долга (не банковского кредита).
struct DebtMeta: Codable, Equatable {
    var direction: DebtDirection
    var counterparty: String?
    var dueDate: Date?
    var rate: Decimal?
}

/// Класс рыночного актива.
enum MarketAssetClass: String, Codable {
    case stock
    case crypto
    case bond
    case metal
}

/// Метаданные рыночного счёта (акции/крипта/облигации/металлы).
struct MarketMeta: Codable, Equatable {
    var symbol: String
    var assetClass: MarketAssetClass
}

/// Метаданные ручного актива (недвижимость/бизнес/другое).
struct ManualAssetMeta: Codable, Equatable {
    var revalReminderMonths: Int?
    var depreciationRatePerYear: Decimal?
    /// Связанный кредит (например, ипотека под недвижимость) — для будущих фаз, не используется в Фазе 0.
    var linkedLoanID: UUID?
}
