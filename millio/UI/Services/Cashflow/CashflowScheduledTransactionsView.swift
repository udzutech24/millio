//
//  CashflowScheduledTransactionsView.swift
//  millio
//
//  Created by Codex on 01.03.2026.
//

import SwiftUI

struct CashflowScheduledTransactionsView: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryKind
    let mode: CashflowScheduledTransactionsMode

    @State private var searchText: String = ""
    @State private var showCreateSheet: Bool = false
    @State private var editingTransaction: CashflowTransaction?
    @State private var pendingDeleteTransaction: CashflowTransaction?
    @State private var showDeleteAlert: Bool = false

    private var transactions: [CashflowTransaction] {
        switch mode {
        case .recurring:
            return viewModel.recurringTemplates(for: kind)
        case .plannedOneTime:
            return viewModel.plannedOneTimeTransactions(for: kind)
        }
    }

    private var filteredTransactions: [CashflowTransaction] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return transactions }

        return transactions.filter { transaction in
            let query = trimmedQuery.lowercased()
            if title(for: transaction).lowercased().contains(query) { return true }
            if subtitle(for: transaction).lowercased().contains(query) { return true }
            if (transaction.note ?? "").lowercased().contains(query) { return true }
            if amountString(for: transaction).lowercased().contains(query) { return true }
            return false
        }
    }

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 12) {
                searchSection

                if filteredTransactions.isEmpty {
                    emptyState
                } else {
                    contentList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .navigationTitle(mode.navigationTitle(for: kind))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(AppColors.textPrimary)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CashflowTransactionEditorView(
                viewModel: viewModel,
                transactionType: kind.transactionType,
                showsTransactionTypeSection: false,
                showsRecurrenceSection: mode.showsRecurrenceSection,
                customNavigationTitle: mode.createNavigationTitle(for: kind),
                initialRecurrenceRule: mode.defaultRecurrenceRule,
                onSave: { showCreateSheet = false }
            )
        }
        .sheet(item: $editingTransaction) { transaction in
            CashflowTransactionEditorView(
                viewModel: viewModel,
                transaction: transaction,
                showsTransactionTypeSection: false,
                showsRecurrenceSection: mode.showsRecurrenceSection,
                customNavigationTitle: mode.editNavigationTitle(for: kind),
                onSave: { editingTransaction = nil }
            )
        }
        .alert("Удалить операцию?", isPresented: $showDeleteAlert) {
            Button("Отмена", role: .cancel) {
                pendingDeleteTransaction = nil
            }
            Button("Удалить", role: .destructive) {
                guard let transactionToDelete = pendingDeleteTransaction else { return }
                viewModel.handle(.deleteTransaction(transactionToDelete))
                pendingDeleteTransaction = nil
            }
        } message: {
            Text("Операция будет удалена без возможности восстановления.")
        }
    }

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            TextField("Поиск операции", text: $searchText)
                .textInputAutocapitalization(.words)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: mode.emptyIcon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)

            Text(mode.emptyTitle(for: kind))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Button(mode.createButtonTitle(for: kind)) {
                showCreateSheet = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredTransactions) { transaction in
                    Button {
                        editingTransaction = transaction
                    } label: {
                        FinancesGlassCard(accentColor: kind.accentColor) {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Image(systemName: icon(for: transaction))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(AppColors.textSecondary)
                                        Text(title(for: transaction))
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .multilineTextAlignment(.leading)

                                        if mode == .recurring {
                                            Text("Ежемесячно")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(AppColors.textSecondary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    Capsule(style: .continuous)
                                                        .fill(Color.white.opacity(0.08))
                                                )
                                        }
                                    }

                                    Text(subtitle(for: transaction))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 8)

                                Text(amountString(for: transaction))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Редактировать") {
                            editingTransaction = transaction
                        }
                        Button("Удалить", role: .destructive) {
                            pendingDeleteTransaction = transaction
                            showDeleteAlert = true
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func title(for transaction: CashflowTransaction) -> String {
        switch kind {
        case .income:
            return viewModel.incomeCategoryDisplayName(for: transaction.incomeCategoryRaw)
        case .expense:
            return viewModel.expenseCategoryDisplayName(for: transaction.expenseCategoryRaw)
        }
    }

    private func icon(for transaction: CashflowTransaction) -> String {
        switch kind {
        case .income:
            return viewModel.categoryOption(
                for: transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue,
                kind: .income
            ).icon
        case .expense:
            return viewModel.categoryOption(
                for: transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue,
                kind: .expense
            ).icon
        }
    }

    private func subtitle(for transaction: CashflowTransaction) -> String {
        var parts: [String] = []
        let plannedDate = transaction.transactionDate

        switch mode {
        case .recurring:
            if let nextDate = viewModel.nextOccurrenceDate(for: transaction) {
                parts.append("Следующая: \(formatDate(nextDate))")
            } else {
                parts.append("Дата старта: \(formatDate(plannedDate))")
            }
        case .plannedOneTime:
            parts.append("Запланировано: \(formatDate(plannedDate))")
        }

        if let cardName = cardName(for: transaction.cardID) {
            parts.append("Счет: \(cardName)")
        }

        if let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            parts.append(note)
        }

        return parts.joined(separator: " • ")
    }

    private func amountString(for transaction: CashflowTransaction) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        let amount = formatter.string(from: NSNumber(value: transaction.amount)) ?? "0"
        return "\(amount) \(transaction.currency)"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private func cardName(for cardID: String?) -> String? {
        guard let cardID else { return nil }
        return viewModel.state.allCards.first(where: { $0.cardUniqueID == cardID })?.name
    }
}

enum CashflowScheduledTransactionsMode: Hashable {
    case recurring
    case plannedOneTime

    var defaultRecurrenceRule: CashflowRecurrenceRule {
        switch self {
        case .recurring:
            return .monthly
        case .plannedOneTime:
            return .none
        }
    }

    var showsRecurrenceSection: Bool {
        switch self {
        case .recurring:
            return true
        case .plannedOneTime:
            return false
        }
    }

    var emptyIcon: String {
        switch self {
        case .recurring:
            return "repeat.circle"
        case .plannedOneTime:
            return "calendar.badge.plus"
        }
    }

    func navigationTitle(for kind: CashflowCategoryKind) -> String {
        switch (self, kind) {
        case (.recurring, .income):
            return "Регулярные доходы"
        case (.recurring, .expense):
            return "Регулярные расходы"
        case (.plannedOneTime, .income):
            return "Запланированные доходы"
        case (.plannedOneTime, .expense):
            return "Запланированные расходы"
        }
    }

    func createNavigationTitle(for kind: CashflowCategoryKind) -> String {
        switch (self, kind) {
        case (.recurring, .income):
            return "Новый регулярный доход"
        case (.recurring, .expense):
            return "Новый регулярный расход"
        case (.plannedOneTime, .income):
            return "Новый запланированный доход"
        case (.plannedOneTime, .expense):
            return "Новый запланированный расход"
        }
    }

    func editNavigationTitle(for kind: CashflowCategoryKind) -> String {
        switch (self, kind) {
        case (.recurring, .income):
            return "Регулярный доход"
        case (.recurring, .expense):
            return "Регулярный расход"
        case (.plannedOneTime, .income):
            return "Запланированный доход"
        case (.plannedOneTime, .expense):
            return "Запланированный расход"
        }
    }

    func emptyTitle(for kind: CashflowCategoryKind) -> String {
        switch (self, kind) {
        case (.recurring, .income):
            return "Регулярные доходы пока не добавлены"
        case (.recurring, .expense):
            return "Регулярные расходы пока не добавлены"
        case (.plannedOneTime, .income):
            return "Нет запланированных доходов"
        case (.plannedOneTime, .expense):
            return "Нет запланированных расходов"
        }
    }

    func createButtonTitle(for kind: CashflowCategoryKind) -> String {
        switch (self, kind) {
        case (.recurring, .income):
            return "Добавить регулярный доход"
        case (.recurring, .expense):
            return "Добавить регулярный расход"
        case (.plannedOneTime, .income):
            return "Добавить запланированный доход"
        case (.plannedOneTime, .expense):
            return "Добавить запланированный расход"
        }
    }
}

private extension CashflowCategoryKind {
    var accentColor: Color {
        switch self {
        case .income:
            return AppColors.incomeGradient.first ?? AppColors.brandPrimary
        case .expense:
            return AppColors.expenseGradient.first ?? AppColors.brandPrimary
        }
    }

    var transactionType: CashflowTransactionType {
        switch self {
        case .income:
            return .income
        case .expense:
            return .expense
        }
    }
}
