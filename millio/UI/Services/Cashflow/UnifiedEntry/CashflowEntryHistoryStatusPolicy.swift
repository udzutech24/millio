import Foundation

enum CashflowEntryHistoryStatus: String, CaseIterable, Sendable {
    case upcoming
    case paid
}

/// Pure contract shared by the future History UI and its tests.
/// It does not infer payment from title, category, or amount.
struct CashflowEntryHistoryStatusPolicy {
    struct CompletedOccurrence: Equatable, Sendable {
        let recurrenceSeriesID: String
        let transactionTypeRaw: String
        let date: Date
    }

    enum Item: Equatable, Sendable {
        /// A persisted manual/imported/generated operation is historical fact.
        case actual(date: Date)
        /// A one-time plan is paid only after its balance effect was applied.
        case oneTimePlan(date: Date, hasAppliedEffect: Bool)
        /// A recurring calendar occurrence links to an actual operation by
        /// series + transaction type + local calendar day.
        case recurringOccurrence(
            date: Date,
            recurrenceSeriesID: String,
            transactionTypeRaw: String
        )

        var date: Date {
            switch self {
            case .actual(let date), .oneTimePlan(let date, _):
                return date
            case .recurringOccurrence(let date, _, _):
                return date
            }
        }
    }

    static func status(
        for item: Item,
        completedOccurrences: [CompletedOccurrence] = [],
        calendar: Calendar = .current
    ) -> CashflowEntryHistoryStatus {
        switch item {
        case .actual:
            return .paid
        case .oneTimePlan(_, let hasAppliedEffect):
            return hasAppliedEffect ? .paid : .upcoming
        case let .recurringOccurrence(date, seriesID, transactionTypeRaw):
            let hasMatch = completedOccurrences.contains { completed in
                completed.recurrenceSeriesID == seriesID
                    && completed.transactionTypeRaw == transactionTypeRaw
                    && calendar.isDate(completed.date, inSameDayAs: date)
            }
            return hasMatch ? .paid : .upcoming
        }
    }
}
