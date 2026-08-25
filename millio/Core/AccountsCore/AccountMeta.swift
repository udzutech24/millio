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
///
/// Тип хранится СТРОКОЙ — и в SwiftData (внутри Codable-структуры `DepositMeta`), и в backup
/// (`DepositMeta.exportDict`). Поэтому rawValue у `none`/`monthly`/`quarterly` заморожены:
/// переименование сделает нечитаемыми уже существующие вклады и старые бэкапы.
/// `RawRepresentable` реализован вручную (а не через `: String`), потому что `customDays`
/// несёт ассоциированное значение — при этом внешнее представление остаётся тем же String,
/// то есть форма хранения не меняется.
enum AccountDepositCapitalization: Hashable, Codable, RawRepresentable {
    case none
    case daily
    case monthly
    case quarterly
    /// Произвольный период начисления, в днях (минимум 1).
    case customDays(Int)

    /// Префикс rawValue произвольного периода: `custom_45` = раз в 45 дней.
    static let customRawPrefix = "custom_"

    /// Варианты для пикеров: `customDays` подставляется отдельно с выбранным пользователем N.
    static let presetCases: [AccountDepositCapitalization] = [.none, .daily, .monthly, .quarterly]

    /// Период в днях для произвольной периодичности; `nil` для календарных режимов.
    var customDays: Int? {
        if case .customDays(let days) = self { return max(1, days) }
        return nil
    }

    /// Только календарные режимы привязаны к числу месяца (`DepositMeta.payoutDay`).
    /// Шаговые (`daily`/`customDays`) считают от даты открытия, число месяца для них бессмысленно.
    var usesMonthlyPayoutDay: Bool {
        switch self {
        case .monthly, .quarterly: true
        case .none, .daily, .customDays: false
        }
    }

    /// Длина периода начисления в днях — для live-превью дохода «за период».
    /// Календарные режимы усредняются (365/12, 365/4), точная дата выплаты — за планировщиком.
    var approximatePeriodDays: Int {
        switch self {
        case .none: 365
        case .daily: 1
        case .monthly: 30
        case .quarterly: 91
        case .customDays(let days): max(1, days)
        }
    }

    var rawValue: String {
        switch self {
        case .none: "none"
        case .daily: "daily"
        case .monthly: "monthly"
        case .quarterly: "quarterly"
        case .customDays(let days): "\(Self.customRawPrefix)\(max(1, days))"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "none": self = .none
        case "daily": self = .daily
        case "monthly": self = .monthly
        case "quarterly": self = .quarterly
        default:
            guard rawValue.hasPrefix(Self.customRawPrefix),
                  let days = Int(rawValue.dropFirst(Self.customRawPrefix.count)),
                  days >= 1 else { return nil }
            self = .customDays(days)
        }
    }
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
    /// Пользовательская пометка «доход по вкладу облагается налогом». Это ТЕГ, а не вход расчёта:
    /// `DepositTaxCalculator` считает НДФЛ глобально по всем вкладам владельца и этот флаг не читает.
    /// Optional намеренно: вклады, созданные до появления тега, декодируются как `nil` (== не размечен)
    /// — non-optional Bool сломал бы синтезированный `init(from:)` на старых записях (keyNotFound).
    var isTaxable: Bool?
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

// MARK: - Backup export/import
//
// Decimal сериализуется СТРОКОЙ, а не JSON-числом: `Account.export()` кладёт эти словари в общий
// backup-словарь, который дважды проходит через `JSONSerialization` (в `ModelTypeRegistry` при сборе
// и ещё раз в `DataRepository.exportAllData`) — на этом пути Decimal бриджится в NSNumber/Double и
// теряет точность. Строка переживает оба прохода без искажений (см. `Decimal(string:)` при импорте).

extension CardMeta {
    func exportDict() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let bank { dict["bank"] = bank }
        if let last4 { dict["last4"] = last4 }
        if let creditLimit { dict["creditLimit"] = "\(creditLimit)" }
        if let statementDay { dict["statementDay"] = statementDay }
        if let dueDay { dict["dueDay"] = dueDay }
        if let minPayment { dict["minPayment"] = "\(minPayment)" }
        if let graceDays { dict["graceDays"] = graceDays }
        if let overdraftLimit { dict["overdraftLimit"] = "\(overdraftLimit)" }
        return dict
    }

    init(exportDict dict: [String: Any]) {
        self.init(
            bank: dict["bank"] as? String,
            last4: dict["last4"] as? String,
            creditLimit: (dict["creditLimit"] as? String).flatMap { Decimal(string: $0) },
            statementDay: dict["statementDay"] as? Int,
            dueDay: dict["dueDay"] as? Int,
            minPayment: (dict["minPayment"] as? String).flatMap { Decimal(string: $0) },
            graceDays: dict["graceDays"] as? Int,
            overdraftLimit: (dict["overdraftLimit"] as? String).flatMap { Decimal(string: $0) }
        )
    }
}

extension DepositMeta {
    func exportDict() -> [String: Any] {
        var dict: [String: Any] = [
            "rate": "\(rate)",
            "capitalization": capitalization.rawValue,
            "allowsTopUp": allowsTopUp,
            "allowsEarlyClose": allowsEarlyClose,
            "remindEnd": remindEnd,
            "autoRollover": autoRollover
        ]
        if let termEnd { dict["termEnd"] = termEnd.timeIntervalSince1970 }
        if let payoutDay { dict["payoutDay"] = payoutDay }
        if let earlyClosePenalty { dict["earlyClosePenalty"] = "\(earlyClosePenalty)" }
        if let isTaxable { dict["isTaxable"] = isTaxable }
        return dict
    }

    /// Failable: `rate`/`capitalization` — обязательные поля модели, без них восстановить нельзя.
    init?(exportDict dict: [String: Any]) {
        guard let rateString = dict["rate"] as? String, let rate = Decimal(string: rateString),
              let capitalizationRaw = dict["capitalization"] as? String,
              let capitalization = AccountDepositCapitalization(rawValue: capitalizationRaw),
              let allowsTopUp = dict["allowsTopUp"] as? Bool,
              let allowsEarlyClose = dict["allowsEarlyClose"] as? Bool,
              let remindEnd = dict["remindEnd"] as? Bool,
              let autoRollover = dict["autoRollover"] as? Bool else {
            return nil
        }
        self.init(
            rate: rate,
            capitalization: capitalization,
            termEnd: (dict["termEnd"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) },
            payoutDay: dict["payoutDay"] as? Int,
            allowsTopUp: allowsTopUp,
            allowsEarlyClose: allowsEarlyClose,
            earlyClosePenalty: (dict["earlyClosePenalty"] as? String).flatMap { Decimal(string: $0) },
            remindEnd: remindEnd,
            autoRollover: autoRollover,
            isTaxable: dict["isTaxable"] as? Bool
        )
    }
}

extension LoanMeta {
    func exportDict() -> [String: Any] {
        var dict: [String: Any] = [
            "principal": "\(principal)",
            "rate": "\(rate)",
            "scheduleType": scheduleType.rawValue
        ]
        if let monthlyPayment { dict["monthlyPayment"] = "\(monthlyPayment)" }
        if let paymentDay { dict["paymentDay"] = paymentDay }
        if let termEnd { dict["termEnd"] = termEnd.timeIntervalSince1970 }
        if let insurance { dict["insurance"] = "\(insurance)" }
        return dict
    }

    /// Failable: `principal`/`rate`/`scheduleType` — обязательные поля модели.
    init?(exportDict dict: [String: Any]) {
        guard let principalString = dict["principal"] as? String, let principal = Decimal(string: principalString),
              let rateString = dict["rate"] as? String, let rate = Decimal(string: rateString),
              let scheduleTypeRaw = dict["scheduleType"] as? String,
              let scheduleType = LoanScheduleType(rawValue: scheduleTypeRaw) else {
            return nil
        }
        self.init(
            principal: principal,
            rate: rate,
            monthlyPayment: (dict["monthlyPayment"] as? String).flatMap { Decimal(string: $0) },
            paymentDay: dict["paymentDay"] as? Int,
            termEnd: (dict["termEnd"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) },
            scheduleType: scheduleType,
            insurance: (dict["insurance"] as? String).flatMap { Decimal(string: $0) }
        )
    }
}

extension DebtMeta {
    func exportDict() -> [String: Any] {
        var dict: [String: Any] = ["direction": direction.rawValue]
        if let counterparty { dict["counterparty"] = counterparty }
        if let dueDate { dict["dueDate"] = dueDate.timeIntervalSince1970 }
        if let rate { dict["rate"] = "\(rate)" }
        return dict
    }

    /// Failable: `direction` — обязательное поле модели.
    init?(exportDict dict: [String: Any]) {
        guard let directionRaw = dict["direction"] as? String,
              let direction = DebtDirection(rawValue: directionRaw) else {
            return nil
        }
        self.init(
            direction: direction,
            counterparty: dict["counterparty"] as? String,
            dueDate: (dict["dueDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) },
            rate: (dict["rate"] as? String).flatMap { Decimal(string: $0) }
        )
    }
}

extension MarketMeta {
    func exportDict() -> [String: Any] {
        ["symbol": symbol, "assetClass": assetClass.rawValue]
    }

    /// Failable: `symbol`/`assetClass` — обязательные поля модели.
    init?(exportDict dict: [String: Any]) {
        guard let symbol = dict["symbol"] as? String,
              let assetClassRaw = dict["assetClass"] as? String,
              let assetClass = MarketAssetClass(rawValue: assetClassRaw) else {
            return nil
        }
        self.init(symbol: symbol, assetClass: assetClass)
    }
}

extension ManualAssetMeta {
    func exportDict() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let revalReminderMonths { dict["revalReminderMonths"] = revalReminderMonths }
        if let depreciationRatePerYear { dict["depreciationRatePerYear"] = "\(depreciationRatePerYear)" }
        if let linkedLoanID { dict["linkedLoanID"] = linkedLoanID.uuidString }
        return dict
    }

    init(exportDict dict: [String: Any]) {
        self.init(
            revalReminderMonths: dict["revalReminderMonths"] as? Int,
            depreciationRatePerYear: (dict["depreciationRatePerYear"] as? String).flatMap { Decimal(string: $0) },
            linkedLoanID: (dict["linkedLoanID"] as? String).flatMap { UUID(uuidString: $0) }
        )
    }
}
