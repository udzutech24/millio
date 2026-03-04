//
//  CashflowTransactionsHistoryView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

// MARK: - History View

struct CashflowTransactionsHistoryView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: CashflowHistoryTypeFilter = .all
    @State private var isSearchActive = false
    @State private var searchText = ""
    @State private var selectedStartDate: Date? = nil
    @State private var selectedEndDate: Date? = nil
    @State private var isDateFilterSheetPresented = false
    @State private var displayedTransactionsLimit = Self.pageSize
    @FocusState private var isSearchFocused: Bool
    private static let pageSize = 20

    /// Транзакции с учетом типа, даты и поиска.
    private var filteredTransactions: [CashflowTransaction] {
        let query = CashflowHistoryQuery(
            typeFilter: selectedFilter,
            searchText: isSearchActive ? searchText : "",
            startDate: selectedStartDate,
            endDate: selectedEndDate
        )
        return viewModel.historyTransactions(matching: query)
    }

    private var visibleTransactions: [CashflowTransaction] {
        Array(filteredTransactions.prefix(displayedTransactionsLimit))
    }

    private var canLoadMore: Bool {
        filteredTransactions.count > visibleTransactions.count
    }

    /// Группировка по дате
    private var groupedTransactions: [(date: Date, transactions: [CashflowTransaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleTransactions) { transaction in
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
            .navigationTitle(String(localized: "cashflow.history.title"))
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
            .sheet(isPresented: $isDateFilterSheetPresented) {
                HistoryDateRangeSheet(
                    startDate: $selectedStartDate,
                    endDate: $selectedEndDate
                )
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CashflowHistoryTypeFilter.allCases, id: \.self) { filter in
                    HistoryFilterChip(
                        title: filter.title,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                            resetPagination()
                        }
                    }
                }

                HistoryDateFilterChip(
                    title: dateFilterTitle,
                    isSelected: isDateFilterActive
                ) {
                    isDateFilterSheetPresented = true
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

            Button {
                isDateFilterSheetPresented = true
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDateFilterActive ? Color(hex: "47D7FF") : AppColors.textSecondary)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .stroke(AppColors.textPrimary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(String(localized: "cashflow.common.cancel")) {
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

            Text(String(localized: "cashflow.history.empty.title"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(
                isSearchActive
                ? String(localized: "cashflow.history.empty.search")
                : String(localized: "cashflow.history.empty.default")
            )
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
        .safeAreaInset(edge: .bottom) {
            if canLoadMore {
                loadMoreButton
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
        .onChange(of: searchText) { _, _ in
            resetPagination()
        }
        .onChange(of: selectedFilter) { _, _ in
            resetPagination()
        }
        .onChange(of: selectedStartDate) { _, _ in
            resetPagination()
        }
        .onChange(of: selectedEndDate) { _, _ in
            resetPagination()
        }
    }

    private var loadMoreButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedTransactionsLimit += Self.pageSize
            }
        } label: {
            Text(String(localized: "cashflow.history.load_more"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var isDateFilterActive: Bool {
        selectedStartDate != nil || selectedEndDate != nil
    }

    private var dateFilterTitle: String {
        guard isDateFilterActive else {
            return String(localized: "cashflow.history.period")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        switch (selectedStartDate, selectedEndDate) {
        case let (start?, end?):
            let normalizedStart = min(start, end)
            let normalizedEnd = max(start, end)
            if Calendar.current.isDate(normalizedStart, inSameDayAs: normalizedEnd) {
                return formatter.string(from: normalizedStart)
            }
            return "\(formatter.string(from: normalizedStart)) - \(formatter.string(from: normalizedEnd))"
        case let (start?, nil):
            return formatter.string(from: start)
        case let (nil, end?):
            return formatter.string(from: end)
        case (nil, nil):
            return String(localized: "cashflow.history.period")
        }
    }

    private func resetPagination() {
        displayedTransactionsLimit = Self.pageSize
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
                .foregroundStyle(isSelected ? Color(hex: "1A2233") : Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(
                            isSelected
                            ? AnyShapeStyle(Color(hex: "A0A0A0"))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(hex: "303238"), Color(hex: "24262B")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Date Filter Chip

private struct HistoryDateFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color(hex: "1A2233") : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(
                        isSelected
                        ? AnyShapeStyle(Color(hex: "A0A0A0"))
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [Color(hex: "303238"), Color(hex: "24262B")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Date Range Sheet

private struct HistoryDateRangeSheet: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var draftStartDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var draftEndDate: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(
                    String(
                        format: String(localized: "cashflow.history.date_range.prefix"),
                        periodTitle
                    )
                )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                CalendarRangeMonthView(startDate: $draftStartDate, endDate: $draftEndDate)
                    .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    Button(String(localized: "cashflow.common.reset")) {
                        startDate = nil
                        endDate = nil
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                    Button(String(localized: "cashflow.common.apply")) {
                        startDate = draftStartDate
                        endDate = draftEndDate
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(String(localized: "cashflow.history.date_filter.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "cashflow.common.dismiss")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
            .onAppear {
                if let start = startDate {
                    draftStartDate = start
                }
                if let end = endDate {
                    draftEndDate = end
                } else {
                    draftEndDate = draftStartDate
                }
            }
        }
    }

    private var periodTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        let start = min(draftStartDate, draftEndDate)
        let end = max(draftStartDate, draftEndDate)
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
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
        let symbol = MonetaCurrency(rawValue: resolvedCurrencyCode)?.symbol ?? resolvedCurrencyCode

        switch transaction.transactionType {
        case .income:
            return "+ \(amountStr) \(symbol)"
        case .expense:
            return "– \(amountStr) \(symbol)"
        default:
            return "\(amountStr) \(symbol)"
        }
    }

    private var resolvedCurrencyCode: String {
        let rawCurrency = transaction.currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !rawCurrency.isEmpty {
            return rawCurrency
        }

        let exchangeCurrency = transaction.exchangeRateCurrency?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        if !exchangeCurrency.isEmpty {
            return exchangeCurrency
        }

        return viewModel.state.displayCurrency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    // MARK: - Описание операции

    private var transactionDescription: String? {
        var parts: [String] = []

        switch transaction.transactionType {
        case .income:
            if let categoryRaw = transaction.incomeCategoryRaw {
                parts.append(viewModel.incomeCategoryDisplayName(for: categoryRaw))
            }
            if let cardName = cardName(for: transaction.cardID) {
                parts.append("на \(cardName)")
            }

        case .expense:
            if let categoryRaw = transaction.expenseCategoryRaw {
                parts.append(viewModel.expenseCategoryDisplayName(for: categoryRaw))
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
