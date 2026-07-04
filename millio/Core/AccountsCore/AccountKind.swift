import Foundation

/// Тип счёта в новом ядре event-sourcing.
/// 11 UI-пресетов (карта/наличка/счёт/вклад/кредит/долг/инвестиции/недвижимость/бизнес/акции/крипта)
/// сворачиваются в 8 kind, которые дальше сворачиваются в 6 поведенческих движков (см. `engine`).
enum AccountKind: String, Codable, CaseIterable {
    case cash
    case debitCard
    case bankAccount
    case deposit
    case loan
    case debt
    case marketInvestment
    case manualAsset

    /// Поведенческий движок реплея (A–F по спеке `specs/2026-07-04-accounts-core.md`).
    var engine: AccountEngine {
        switch self {
        case .cash, .debitCard, .bankAccount:
            return .cashLike
        case .deposit:
            return .deposit
        case .loan:
            return .loan
        case .debt:
            return .debt
        case .marketInvestment:
            return .market
        case .manualAsset:
            return .manualAsset
        }
    }
}

/// 6 поведенческих движков расчёта баланса (A–F).
enum AccountEngine {
    case cashLike       // A: cash/debitCard/bankAccount
    case deposit        // B: deposit (= A + interest)
    case loan           // C: loan — обязательство, отрицательный итог не обрезается
    case debt           // D: debt — знак задаёт направление событий
    case market         // E: marketInvestment — quantity × price(date)
    case manualAsset    // F: manualAsset — последняя revaluation
}
