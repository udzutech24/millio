import Foundation

enum CashflowUpcomingFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expenses

    var id: String { rawValue }

    func includes(_ item: CashflowUpcomingItem) -> Bool {
        switch self {
        case .all: true
        case .income: item.kind == .income
        case .expenses: item.kind == .expense
        }
    }
}

struct CashflowUpcomingDaySection: Identifiable, Equatable {
    let day: Date
    let items: [CashflowUpcomingItem]
    var id: Date { day }
}

enum CashflowUpcomingPresentation {
    static func sections(
        from items: [CashflowUpcomingItem],
        filter: CashflowUpcomingFilter,
        calendar: Calendar
    ) -> [CashflowUpcomingDaySection] {
        let filtered = items.filter(filter.includes).sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            CashflowUpcomingDaySection(day: day, items: grouped[day] ?? [])
        }
    }
}

enum CashflowUpcomingAccountResolver {
    static func resolve(accountID: UUID, in accounts: [Account]) -> Account? {
        accounts.first { $0.id == accountID && $0.deletedAt == nil }
    }
}
