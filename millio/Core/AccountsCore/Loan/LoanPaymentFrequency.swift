import Foundation

/// Периодичность платежа по кредиту.
///
/// Отдельный enum, а не расширение `AccountDepositCapitalization`: у капитализации вклада другая
/// семантика (`.daily`/`.customDays`) и нет полугодового/годового шага. Единственное, что нужно
/// расчёту, — шаг в месяцах, поэтому кейсы кратны месяцу и делят год нацело.
enum LoanPaymentFrequency: String, CaseIterable, Codable, Sendable {
    case monthly
    case every2Months
    case quarterly
    case semiannual
    case annual

    var stepMonths: Int {
        switch self {
        case .monthly: return 1
        case .every2Months: return 2
        case .quarterly: return 3
        case .semiannual: return 6
        case .annual: return 12
        }
    }

    /// Делится нацело всегда: все шаги — делители 12. Это и есть причина, по которой в enum нет
    /// произвольного шага в днях.
    var periodsPerYear: Int { 12 / stepMonths }
}
