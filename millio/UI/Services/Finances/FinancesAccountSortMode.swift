import Foundation

enum AccountSortMode: String, CaseIterable {
    case amountDescending = "amount_desc"
    case amountAscending = "amount_asc"
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"

    var title: String {
        switch self {
        case .amountDescending: return "По сумме: больше → меньше"
        case .amountAscending: return "По сумме: меньше → больше"
        case .nameAscending: return "По имени: А → Я"
        case .nameDescending: return "По имени: Я → А"
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
