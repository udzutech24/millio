//
//  CashflowTransactionsHistoryView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

// MARK: - Фильтр истории

private enum HistoryFilter: CaseIterable {
    case all, income, expense, transfer

    var title: String {
        switch self {
        case .all: return "Все"
        case .income: return "Пополнения"
        case .expense: return "Списания"
        case .transfer: return "Переводы"
        }
    }

    func matches(_ type: CashflowTransactionType) -> Bool {
        switch self {
        case .all: return true
        case .income: return type == .income
        case .expense: return type == .expense
        case .transfer: return type == .transfer
        }
    }
}

// MARK: - History View

struct CashflowTransactionsHistoryView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: HistoryFilter = .all
    @State private var isSearchActive = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    /// Транзакции с учётом фильтра и поиска
    private var filteredTransactions: [CashflowTransaction] {
        var result = viewModel.state.filteredTransactions

        // Фильтр по типу
        if selectedFilter != .all {
            result = result.filter { selectedFilter.matches($0.transactionType) }
        }

        // Поиск
        if isSearchActive && !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { transaction in
                if let note = transaction.note, note.lowercased().contains(query) { return true }
                if let cat = transaction.incomeCategory?.displayName.lowercased(), cat.contains(query) { return true }
                if let cat = transaction.expenseCategory?.displayName.lowercased(), cat.contains(query) { return true }
                if transaction.transactionType.displayName.lowercased().contains(query) { return true }
                let amountStr = String(format: "%.0f", transaction.amount)
                if amountStr.contains(query) { return true }
                if let cardID = transaction.cardID,
                   let card = viewModel.state.allCards.first(where: { $0.cardUniqueID == cardID }),
                   card.name.lowercased().contains(query) { return true }
                return false
            }
        }

        return result
    }

    /// Группировка по дате
    private var groupedTransactions: [(date: Date, transactions: [CashflowTransaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            calendar.startOfDay(for: transaction.transactionDate)
        }
        return grouped.sorted { $0.key > $1.key }
            .map { (date: $0.key, transactions: $0.value) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 0) {
                    // Поиск или фильтр
                    if isSearchActive {
                        searchBar
                    } else {
                        filterChips
                    }

                    if filteredTransactions.isEmpty {
                        emptyState
                    } else {
                        transactionsList
                    }
                }
            }
            .navigationTitle("История операций")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }

                if !isSearchActive {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSearchActive = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isSearchFocused = true
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    HistoryFilterChip(
                        title: filter.title,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textSecondary)

                TextField("", text: $searchText)
                    .foregroundStyle(AppColors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .stroke(AppColors.textPrimary.opacity(0.3), lineWidth: 1)
            )

            Button("Отменить") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSearchActive = false
                    searchText = ""
                    isSearchFocused = false
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.textTertiary)

            Text("Нет операций")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(isSearchActive ? "Попробуйте изменить запрос" : "Добавьте первую операцию")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Transactions List

    private var transactionsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(groupedTransactions.enumerated()), id: \.element.date) { index, group in
                    // Разделитель с датой (не для первой группы)
                    if index > 0 {
                        Text(formatSectionDate(group.date))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 4)
                    }

                    ForEach(group.transactions) { transaction in
                        VStack(alignment: .leading, spacing: 8) {
                            // Заголовок типа операции
                            FinancesSectionHeader(title: transaction.transactionType.displayName)

                            // Карточка операции
                            HistoryTransactionCard(
                                transaction: transaction,
                                viewModel: viewModel
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private func formatSectionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - History Filter Chip

private struct HistoryFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : AppColors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: AppColors.cashflowGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    } else {
                        Capsule()
                            .stroke(AppColors.textPrimary.opacity(0.2), lineWidth: 1)
                    }
                }
        }
    }
}

// MARK: - History Transaction Card

private struct HistoryTransactionCard: View {
    let transaction: CashflowTransaction
    @ObservedObject var viewModel: CashflowViewModel

    var body: some View {
        Button {
            viewModel.handle(.editTransaction(transaction))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Сумма с префиксом +/–
                Text(formattedAmount)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)

                // Описание операции
                if let description = transactionDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                GlassBackground(
                    gradient: AppColors.cashflowGradient,
                    cornerRadius: 16,
                    strokeWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Форматирование суммы

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0

        let amountStr = formatter.string(from: NSNumber(value: transaction.amount)) ?? "0"
        let symbol = currencySymbol(transaction.currency)

        switch transaction.transactionType {
        case .income:
            return "+ \(amountStr) \(symbol)"
        case .expense:
            return "– \(amountStr) \(symbol)"
        default:
            return "\(amountStr) \(symbol)"
        }
    }

    private func currencySymbol(_ code: String) -> String {
        switch code {
        case "RUB": return "₽"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY", "CNY": return "¥"
        default: return code
        }
    }

    // MARK: - Описание операции

    private var transactionDescription: String? {
        var parts: [String] = []

        switch transaction.transactionType {
        case .income:
            if let category = transaction.incomeCategory {
                parts.append(category.displayName)
            }
            if let cardName = cardName(for: transaction.cardID) {
                parts.append("на \(cardName)")
            }

        case .expense:
            if let category = transaction.expenseCategory {
                parts.append(category.displayName)
            }
            if let cardName = cardName(for: transaction.cardID) {
                parts.append("с \(cardName)")
            }

        case .transfer:
            if let fromName = cardName(for: transaction.cardID),
               let toName = cardName(for: transaction.toCardID) {
                parts.append("\(fromName) → \(toName)")
            }

        default:
            if let cardName = cardName(for: transaction.cardID) {
                parts.append(cardName)
            }
        }

        if let note = transaction.note, !note.isEmpty {
            parts.append(note)
        }

        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    private func cardName(for cardID: String?) -> String? {
        guard let cardID else { return nil }
        return viewModel.state.allCards.first(where: { $0.cardUniqueID == cardID })?.name
    }
}
