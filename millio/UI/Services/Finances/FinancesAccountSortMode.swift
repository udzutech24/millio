import Foundation

enum AccountSortMode: String, CaseIterable {
    case amountDescending = "amount_desc"
    case amountAscending = "amount_asc"
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"

    var title: String {
        switch self {
        case .amountDescending: return FinancesL10n.tr("finances.settings.sort.amount_desc")
        case .amountAscending:  return FinancesL10n.tr("finances.settings.sort.amount_asc")
        case .nameAscending:    return FinancesL10n.tr("finances.settings.sort.name_asc")
        case .nameDescending:   return FinancesL10n.tr("finances.settings.sort.name_desc")
        }
    }

    var icon: String {
        switch self {
        case .amountDescending: return "arrow.down.circle"
        case .amountAscending: return "arrow.up.circle"
        case .nameAscending: return "textformat.abc"
        case .nameDescending: return "textformat.abc.dottedunderline"
        }
    }
}
