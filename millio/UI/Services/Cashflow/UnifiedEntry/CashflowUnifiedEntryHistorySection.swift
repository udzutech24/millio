import SwiftUI

struct CashflowUnifiedEntryHistorySection: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryTransactionSheetKind
    let month: Date
    let onOpenPaidHistory: () -> Void
    let onOpenUpcoming: () -> Void

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
        // Ближайшие к сегодня — и в прошлое, и в будущее: так свежие факты и ближайший план
        // стоят рядом, а далёкий план не вытесняет вчерашнюю покупку.
        return (actual + upcoming).sorted { abs($0.date.timeIntervalSinceNow) < abs($1.date.timeIntervalSinceNow) }
    }

    private static let visibleRowCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("cashflow.entry.more.section.operations", defaultValue: "Operations"))
                    .font(.millioSubheadline)
                Spacer()
                Button(L("cashflow.history.title", defaultValue: "History"), action: onOpenPaidHistory)
                    .font(.millioCallout)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityIdentifier("cashflow.unified.history.open")
            }

            if rows.isEmpty {
                Text(emptyText)
                    .font(.millioCallout)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ForEach(rows.prefix(Self.visibleRowCount)) { row in
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
                                    .font(.millioCallout)
                                    .lineLimit(1)
                                Text(subtitle(for: row))
                                    .font(.millioCaption2Regular)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                            Text(cashflowHistoryAmountText(row.transaction.amount))
                                .font(.millioCalloutSemibold)
                                .foregroundStyle(row.status == .paid ? AppColors.textPrimary : AppColors.textSecondary)
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppSpacing.ml)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private var emptyText: String {
        L("cashflow.history.empty.filtered", defaultValue: "No operations for this month")
    }

    private func subtitle(for row: Row) -> String {
        let date = row.date.formatted(date: .abbreviated, time: .omitted)
        guard row.status == .upcoming else { return date }
        return "\(date) · \(L("cashflow.entry.history.planned_mark", defaultValue: "planned"))"
    }

    private func categoryIcon(for transaction: CashflowTransaction) -> String {
        let raw = kind == .income
            ? (transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue)
            : (transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue)
        return viewModel.categoryOptions(for: kind.categoryKind).first { $0.rawValue == raw }?.icon ?? "circle"
    }
}
