import SwiftUI

struct CashflowUnifiedEntryHistorySection: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryTransactionSheetKind
    let month: Date
    let onOpenPaidHistory: () -> Void
    let onOpenUpcoming: () -> Void

    @State private var filter: CashflowEntryHistoryFilter = .all

    private struct Row: Identifiable {
        let id: String
        let transaction: CashflowTransaction
        let date: Date
        let status: CashflowEntryHistoryStatus
    }

    private var rows: [Row] {
        let calendar = Calendar.current
        let actual = viewModel.state.transactions.compactMap { transaction -> Row? in
            guard transaction.transactionType == kind.transactionType,
                  !transaction.isRecurringTemplate,
                  calendar.isDate(transaction.transactionDate, equalTo: month, toGranularity: .month),
                  transaction.transactionDate <= .now || transaction.hasAppliedBalanceEffect else { return nil }
            return Row(id: "actual-\(transaction.uniqueID)", transaction: transaction, date: transaction.transactionDate, status: .paid)
        }
        let upcoming = viewModel.scheduledCalendarEntries(for: kind.categoryKind, month: month).map { entry in
            Row(id: "upcoming-\(entry.id)", transaction: entry.transaction, date: entry.scheduledDate, status: .upcoming)
        }
        return (actual + upcoming)
            .filter { filter.includes($0.status) }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .upcoming }
                return lhs.status == .upcoming ? lhs.date < rhs.date : lhs.date > rhs.date
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("cashflow.history.title", defaultValue: "History"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(L("cashflow.category.show_all", defaultValue: "Show all"), action: onOpenPaidHistory)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Picker(L("cashflow.history.status", defaultValue: "Status"), selection: $filter) {
                Text(L("cashflow.history.status.all", defaultValue: "All")).tag(CashflowEntryHistoryFilter.all)
                Text(L("cashflow.history.status.upcoming", defaultValue: "Upcoming")).tag(CashflowEntryHistoryFilter.upcoming)
                Text(L("cashflow.history.status.paid", defaultValue: "Paid")).tag(CashflowEntryHistoryFilter.paid)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("cashflow.unified.history.status")

            if rows.isEmpty {
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ForEach(rows.prefix(5)) { row in
                    Button {
                        row.status == .paid ? onOpenPaidHistory() : onOpenUpcoming()
                    } label: {
                        HStack(spacing: 10) {
                            CashflowCategoryIconView(
                                icon: categoryIcon(for: row.transaction),
                                fontSize: 14,
                                fontWeight: .semibold,
                                tint: AnyShapeStyle(AppColors.textPrimary)
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cashflowHistoryPrimaryTitle(for: row.transaction))
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(row.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                            Text(cashflowHistoryAmountText(row.transaction.amount))
                                .font(.system(size: 13, weight: .semibold))
                            Text(row.status == .paid ? "✓" : "○")
                                .foregroundStyle(row.status == .paid ? Color.green : AppColors.textSecondary)
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private var emptyText: String {
        switch filter {
        case .all: return L("cashflow.history.empty.filtered", defaultValue: "No operations for this month")
        case .upcoming: return L("cashflow.history.empty.upcoming", defaultValue: "No upcoming operations for this month")
        case .paid: return L("cashflow.history.empty.paid", defaultValue: "No paid operations for this month")
        }
    }

    private func categoryIcon(for transaction: CashflowTransaction) -> String {
        let raw = kind == .income
            ? (transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue)
            : (transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue)
        return viewModel.categoryOptions(for: kind.categoryKind).first { $0.rawValue == raw }?.icon ?? "circle"
    }
}
