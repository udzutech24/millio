//
//  CashflowTransactionsHistoryView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

private func cashflowHistoryLocalizedText(
    _ key: String,
    locale: Locale,
    ru: String,
    en: String,
    zhHans: String? = nil
) -> String {
    let localized = AppLocalization.string(key, locale: locale)
    guard localized == key else { return localized }
    return FinancesL10n.text(locale: locale, ru: ru, en: en, zhHans: zhHans)
}

private func cashflowHistoryTr(_ key: String, fallback: String? = nil) -> String {
    AppLocalization.string(key, locale: AppLocalization.currentAppLocale, fallback: fallback)
}

func cashflowHistoryAmountText(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.decimalSeparator = ","
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    formatter.groupingSize = 3
    formatter.secondaryGroupingSize = 3
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: amount)) ?? "0"
}

func cashflowHistoryWholeAmountText(_ amount: Double) -> String {
    cashflowHistoryFormattedNumberText(amount, maxFractionDigits: 0)
}

func cashflowHistoryFormattedNumberText(
    _ amount: Double,
    maxFractionDigits: Int
) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.decimalSeparator = ","
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    formatter.groupingSize = 3
    formatter.secondaryGroupingSize = 3
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = max(0, maxFractionDigits)
    return formatter.string(from: NSNumber(value: amount)) ?? "0"
}

func cashflowHistoryAssetChangeLines(
    for transaction: CashflowTransaction,
    currencyCode: String,
    locale: Locale = AppLocalization.currentAppLocale
) -> [String] {
    guard transaction.hasAssetChangeSnapshot else { return [] }

    let quantityTitle = cashflowHistoryLocalizedText(
        "cashflow.history.asset_change.quantity",
        locale: locale,
        ru: "Кол-во",
        en: "Qty",
        zhHans: "数量"
    )
    let priceTitle = cashflowHistoryLocalizedText(
        "cashflow.history.asset_change.price",
        locale: locale,
        ru: "Цена",
        en: "Price",
        zhHans: "价格"
    )
    let amountTitle = cashflowHistoryLocalizedText(
        "cashflow.history.asset_change.value",
        locale: locale,
        ru: "Стоимость",
        en: "Value",
        zhHans: "价值"
    )
    let epsilon = 0.0000001

    func appendLine(
        _ lines: inout [String],
        title: String,
        before: Double?,
        after: Double?,
        maxFractionDigits: Int,
        suffix: String = ""
    ) {
        guard let before, let after, abs(before - after) > epsilon else { return }
        let beforeText = cashflowHistoryFormattedNumberText(before, maxFractionDigits: maxFractionDigits)
        let afterText = cashflowHistoryFormattedNumberText(after, maxFractionDigits: maxFractionDigits)
        lines.append("\(title): \(beforeText)\(suffix) -> \(afterText)\(suffix)")
    }

    let normalizedCurrency = currencyCode
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
    let currencySuffix = normalizedCurrency.isEmpty ? "" : " \(normalizedCurrency)"

    var lines: [String] = []
    appendLine(
        &lines,
        title: quantityTitle,
        before: transaction.assetQuantityBefore,
        after: transaction.assetQuantityAfter,
        maxFractionDigits: 8
    )
    appendLine(
        &lines,
        title: priceTitle,
        before: transaction.assetUnitPriceBefore,
        after: transaction.assetUnitPriceAfter,
        maxFractionDigits: 4,
        suffix: currencySuffix
    )
    appendLine(
        &lines,
        title: amountTitle,
        before: transaction.assetAmountBefore,
        after: transaction.assetAmountAfter,
        maxFractionDigits: 2,
        suffix: currencySuffix
    )
    return lines
}

func cashflowHistoryAssetChangeSummary(
    for transaction: CashflowTransaction,
    currencyCode: String,
    locale: Locale = AppLocalization.currentAppLocale
) -> String? {
    let lines = cashflowHistoryAssetChangeLines(
        for: transaction,
        currencyCode: currencyCode,
        locale: locale
    )
    return lines.isEmpty ? nil : lines.joined(separator: ". ")
}

func cashflowHistoryResolvedTransaction(
    for transaction: CashflowTransaction,
    in transactions: [CashflowTransaction]
) -> CashflowTransaction {
    transactions.first(where: { $0.persistentModelID == transaction.persistentModelID }) ?? transaction
}

func cashflowHistoryTimeToken(for date: Date?) -> String {
    guard let date else { return "0" }
    let timestamp = date.timeIntervalSince1970
    guard timestamp.isFinite, !timestamp.isNaN else { return "0" }
    return String(Int(timestamp.rounded(.towardZero)))
}

enum CashflowHistorySettlementDirection {
    case debit
    case credit
}

struct CashflowHistorySettlementAccountContext: Equatable {
    let cardID: String
    let direction: CashflowHistorySettlementDirection
}

func cashflowHistoryRelatedTransactions(
    for transaction: CashflowTransaction,
    in transactions: [CashflowTransaction]
) -> [CashflowTransaction] {
    guard let operationGroupID = transaction.operationGroupID?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !operationGroupID.isEmpty else {
        return []
    }

    return transactions.filter {
        $0.persistentModelID != transaction.persistentModelID
            && $0.operationGroupID == operationGroupID
    }
}

func cashflowHistorySettlementAccountContext(
    for transaction: CashflowTransaction,
    in transactions: [CashflowTransaction]
) -> CashflowHistorySettlementAccountContext? {
    switch transaction.transactionType {
    case .expense:
        if let cardID = transaction.cardID, !cardID.isEmpty {
            return CashflowHistorySettlementAccountContext(cardID: cardID, direction: .debit)
        }
    case .income:
        if let cardID = transaction.cardID, !cardID.isEmpty {
            return CashflowHistorySettlementAccountContext(cardID: cardID, direction: .credit)
        }
    case .transfer:
        return nil
    case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
        break
    }

    for related in cashflowHistoryRelatedTransactions(for: transaction, in: transactions) {
        switch related.transactionType {
        case .expense:
            if let cardID = related.cardID, !cardID.isEmpty {
                return CashflowHistorySettlementAccountContext(cardID: cardID, direction: .debit)
            }
        case .income:
            if let cardID = related.cardID, !cardID.isEmpty {
                return CashflowHistorySettlementAccountContext(cardID: cardID, direction: .credit)
            }
        case .transfer, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            continue
        }
    }

    if let cardID = transaction.cardID, !cardID.isEmpty {
        return CashflowHistorySettlementAccountContext(cardID: cardID, direction: .debit)
    }

    return nil
}

func cashflowHistoryPrimaryTitle(
    for transaction: CashflowTransaction,
    locale: Locale = AppLocalization.currentAppLocale
) -> String {
    let trimmedNote = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmedNote.isEmpty else { return transaction.transactionType.displayName }

    func localizedInvestmentTradeTitleIfNeeded() -> String? {
        func matchesLocalizedNote(key: String) -> Bool {
            if trimmedNote == key {
                return true
            }

            let candidateLocales = cashflowHistoryLocalizationCandidates(for: locale)
            let localizedValues = candidateLocales.map { candidate in
                AppLocalization.string(key, locale: candidate)
            }
            return localizedValues.contains(trimmedNote)
        }

        if matchesLocalizedNote(key: "finances.transaction.note.investment_buy") {
            return cashflowHistoryLocalizedText(
                "finances.transaction.note.investment_buy",
                locale: locale,
                ru: "Покупка актива",
                en: "Asset purchase"
            )
        }

        if matchesLocalizedNote(key: "finances.transaction.note.investment_sell") {
            return cashflowHistoryLocalizedText(
                "finances.transaction.note.investment_sell",
                locale: locale,
                ru: "Продажа актива",
                en: "Asset sale"
            )
        }

        return nil
    }

    switch transaction.transactionType {
    case .balanceAdjustment:
        if transaction.investmentID != nil {
            return localizedInvestmentTradeTitleIfNeeded() ?? trimmedNote
        }
        return transaction.transactionType.displayName
    case .expense, .income:
        if !transaction.shouldAffectCashflowTotals && transaction.investmentID != nil {
            return localizedInvestmentTradeTitleIfNeeded() ?? trimmedNote
        }
        return transaction.transactionType.displayName
    case .transfer, .cardBalanceAdjustment, .creditDebtAdjustment:
        return transaction.transactionType.displayName
    }
}

private func cashflowHistoryLocalizationCandidates(for locale: Locale) -> [Locale] {
    let candidates = [
        locale,
        Locale(identifier: "ru_RU"),
        Locale(identifier: "en_US"),
        Locale(identifier: "zh-Hans")
    ]

    var seen = Set<String>()
    return candidates.filter { candidate in
        let identifier = candidate.identifier.lowercased()
        guard !seen.contains(identifier) else { return false }
        seen.insert(identifier)
        return true
    }
}

func cashflowHistoryAccountLabel(
    for direction: CashflowHistorySettlementDirection,
    transaction: CashflowTransaction? = nil,
    locale: Locale = AppLocalization.currentAppLocale
) -> String {
    if direction == .debit,
       let transaction,
       cashflowHistoryUsesDedicatedSettlementLabel(for: transaction) {
        return AppLocalization.string(
            "cashflow.history.detail.settlement_account",
            locale: locale,
            fallback: cashflowHistoryLocalizedText(
                "cashflow.history.detail.settlement_account",
                locale: locale,
                ru: "Счет списания",
                en: "Settlement account",
                zhHans: "结算账户"
            )
        )
    }

    switch direction {
    case .debit:
        return cashflowHistoryLocalizedText(
            "cashflow.history.detail.from_account",
            locale: locale,
            ru: "Счет списания",
            en: "From account",
            zhHans: "支出账户"
        )
    case .credit:
        return cashflowHistoryLocalizedText(
            "cashflow.history.detail.to_account",
            locale: locale,
            ru: "Счет зачисления",
            en: "To account",
            zhHans: "入账账户"
        )
    }
}

private func cashflowHistoryUsesDedicatedSettlementLabel(for transaction: CashflowTransaction) -> Bool {
    if transaction.transactionType == .balanceAdjustment, transaction.investmentID != nil {
        return true
    }

    return (transaction.transactionType == .expense || transaction.transactionType == .income)
        && transaction.investmentID != nil
        && transaction.shouldAffectCashflowTotals == false
}

func cashflowHistoryDescription(
    for transaction: CashflowTransaction,
    relatedTransactions: [CashflowTransaction],
    cardNameResolver: (String?) -> String?,
    investmentNameResolver: (String?) -> String?,
    incomeCategoryResolver: (String?) -> String,
    expenseCategoryResolver: (String?) -> String,
    locale: Locale = AppLocalization.currentAppLocale
) -> String? {
    var parts: [String] = []

    switch transaction.transactionType {
    case .income:
        if let raw = transaction.incomeCategoryRaw {
            parts.append(incomeCategoryResolver(raw))
        }
    case .expense:
        if let raw = transaction.expenseCategoryRaw {
            parts.append(expenseCategoryResolver(raw))
        }
    case .transfer:
        if let fromName = cardNameResolver(transaction.cardID),
           let toName = cardNameResolver(transaction.toCardID) {
            parts.append("\(fromName) -> \(toName)")
        }
    case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
        if let investmentName = investmentNameResolver(transaction.investmentID) {
            parts.append(investmentName)
        }
    }

    if let context = cashflowHistorySettlementAccountContext(
        for: transaction,
        in: relatedTransactions
    ), let cardName = cardNameResolver(context.cardID) {
        parts.append(
            "\(cashflowHistoryAccountLabel(for: context.direction, transaction: transaction, locale: locale)): \(cardName)"
        )
    } else {
        switch transaction.transactionType {
        case .expense:
            if let cardName = cardNameResolver(transaction.cardID) {
                parts.append(
                    "\(cashflowHistoryAccountLabel(for: .debit, transaction: transaction, locale: locale)): \(cardName)"
                )
            }
        case .income:
            if let cardName = cardNameResolver(transaction.cardID) {
                parts.append(
                    "\(cashflowHistoryAccountLabel(for: .credit, transaction: transaction, locale: locale)): \(cardName)"
                )
            }
        case .transfer, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            break
        }
    }

    if let assetChangeSummary = cashflowHistoryAssetChangeSummary(
        for: transaction,
        currencyCode: transaction.currency,
        locale: locale
    ), !assetChangeSummary.isEmpty {
        parts.append(assetChangeSummary)
    }

    let trimmedNote = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let primaryTitle = cashflowHistoryPrimaryTitle(for: transaction, locale: locale)
    if !trimmedNote.isEmpty && trimmedNote != primaryTitle {
        parts.append(trimmedNote)
    }

    return parts.isEmpty ? nil : parts.joined(separator: ". ")
}

// MARK: - History View

struct CashflowTransactionsHistoryView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    private let showsDismissButton: Bool
    @State private var selectedFilter: CashflowHistoryTypeFilter
    @State private var selectedSummaryCategoryRawValue: String?
    @State private var summaryModel: CashflowHistorySummaryModel
    @State private var selectedCardID: String?
    private let initialCategoryRawValue: String?
    @State private var isSearchActive = false
    @State private var searchText = ""
    @State private var selectedStartDate: Date?
    @State private var selectedEndDate: Date?
    @State private var isDateFilterSheetPresented = false
    @State private var isCardFilterSheetPresented = false
    @State private var displayedTransactionsLimit = Self.pageSize
    @State private var selectedTransaction: CashflowTransaction?
    @State private var summaryCollapseProgress: CGFloat = 0
    @FocusState private var isSearchFocused: Bool
    private static let pageSize = 20

    init(
        viewModel: CashflowViewModel,
        showsDismissButton: Bool = true,
        initialFilter: CashflowHistoryTypeFilter = .all,
        initialCategoryRawValue: String? = nil,
        initialCardID: String? = nil,
        initialStartDate: Date? = nil,
        initialEndDate: Date? = nil
    ) {
        self.viewModel = viewModel
        self.showsDismissButton = showsDismissButton
        self.initialCategoryRawValue = initialCategoryRawValue
        let defaultRange = CashflowViewModel.defaultPeriodRange(referenceDate: Date(), calendar: .current)
        _selectedFilter = State(initialValue: initialFilter)
        _selectedCardID = State(initialValue: initialCardID)
        _selectedStartDate = State(initialValue: initialStartDate ?? defaultRange.start)
        _selectedEndDate = State(initialValue: initialEndDate ?? defaultRange.end)
        _summaryModel = State(
            initialValue: CashflowHistorySummaryModel.empty(
                mode: .expense,
                currencyCode: viewModel.state.displayCurrency
            )
        )
    }

    /// Транзакции с учетом типа, даты и поиска.
    private var filteredTransactions: [CashflowTransaction] {
        let query = CashflowHistoryQuery(
            typeFilter: selectedFilter,
            searchText: isSearchActive ? searchText : "",
            startDate: selectedStartDate,
            endDate: selectedEndDate,
            cardID: selectedCardID,
            categoryRawValue: initialCategoryRawValue
        )
        return viewModel.historyTransactions(matching: query).filter(matchesSelectedSummaryCategory)
    }

    private var visibleTransactions: [CashflowTransaction] {
        Array(filteredTransactions.prefix(displayedTransactionsLimit))
    }

    private var canLoadMore: Bool {
        filteredTransactions.count > visibleTransactions.count
    }

    private var summaryMode: CashflowHistorySummaryMode {
        switch selectedFilter {
        case .income:
            return .income
        case .expense, .all, .transfer, .assetBalanceChange, .accountBalanceCorrection:
            return .expense
        }
    }

    private var summaryQuery: CashflowHistoryQuery {
        CashflowHistoryQuery(
            typeFilter: .all,
            searchText: "",
            startDate: selectedStartDate,
            endDate: selectedEndDate,
            cardID: selectedCardID,
            categoryRawValue: initialCategoryRawValue
        )
    }

    private var shouldShowSummary: Bool {
        CashflowHistorySummaryPresentation.shouldShow(
            selectedFilter: selectedFilter,
            isSearchActive: isSearchActive,
            searchText: searchText,
            entryCount: summaryModel.entries.count,
            totalAmount: summaryModel.totalAmount
        )
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
                    if isSearchActive {
                        searchBar
                    } else {
                        filterChips
                    }

                    if filteredTransactions.isEmpty {
                        emptyState
                    } else {
                        transactionsListWithSummary
                    }
                }
            }
            .navigationTitle(cashflowHistoryTr("cashflow.history.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
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
                    endDate: $selectedEndDate,
                    resetToDefaultRange: resetDateFilterToDefault
                )
            }
            .sheet(isPresented: $isCardFilterSheetPresented) {
                HistoryCardFilterSheet(
                    cards: viewModel.state.allCards,
                    selectedCardID: $selectedCardID
                )
            }
            .navigationDestination(item: $selectedTransaction) { transaction in
                HistoryTransactionDetailView(
                    transaction: transaction,
                    viewModel: viewModel
                )
            }
            .task(id: summaryReloadKey) {
                await reloadSummary()
            }
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    HistoryDateFilterChip(
                        title: dateFilterTitle,
                        isSelected: true
                    ) {
                        isDateFilterSheetPresented = true
                    }

                    HistoryTypeFilterChip(
                        selectedFilter: selectedFilter,
                        onSelect: { filter in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedFilter = filter
                                resetPagination()
                            }
                        },
                        onReset: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedFilter = .all
                                resetPagination()
                            }
                        }
                    )

                    HistoryCardFilterChip(
                        title: selectedCardTitle ?? cashflowHistoryTr(
                            "cashflow.history.cards",
                            fallback: "Счета и карты"
                        ),
                        isSelected: selectedCardID != nil
                    ) {
                        isCardFilterSheetPresented = true
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 10)
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
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(CashflowHistoryChrome.quietFill)
                    .overlay(
                        Capsule()
                            .stroke(CashflowHistoryChrome.subduedStroke, lineWidth: 0.9)
                    )
            )

            Button {
                isDateFilterSheetPresented = true
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDateFilterCustomized ? CashflowHistoryChrome.accentColor : AppColors.textSecondary)
                    .frame(width: CashflowHistoryChrome.toolbarControlSize, height: CashflowHistoryChrome.toolbarControlSize)
                    .background(
                        Circle()
                            .fill(CashflowHistoryChrome.quietFill)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isDateFilterCustomized
                                        ? CashflowHistoryChrome.selectionStroke
                                        : CashflowHistoryChrome.subduedStroke,
                                        lineWidth: 0.9
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)

            Button(cashflowHistoryTr("cashflow.common.cancel")) {
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

            Text(cashflowHistoryTr("cashflow.history.empty.title"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(
                isSearchActive
                ? cashflowHistoryTr("cashflow.history.empty.search")
                : cashflowHistoryTr("cashflow.history.empty.default")
            )
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Transactions List

    private var transactionsListWithSummary: some View {
        transactionsList
    }

    private var transactionsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if shouldShowSummary {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CashflowHistorySummaryMinYPreferenceKey.self,
                            value: proxy.frame(in: .named("cashflowHistoryScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    CashflowHistorySummaryResponsiveContainer(
                        summary: summaryModel,
                        selectedCategoryRawValue: $selectedSummaryCategoryRawValue,
                        collapseProgress: summaryCollapseProgress
                    )
                    .padding(.bottom, 8)
                }

                ForEach(Array(groupedTransactions.enumerated()), id: \.element.date) { index, group in
                    // Разделитель с датой (не для первой группы)
                    if index > 0 {
                        Text(formatSectionDate(group.date))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    }

                    ForEach(group.transactions) { transaction in
                        VStack(alignment: .leading, spacing: 5) {
                            // Заголовок типа операции
                            FinancesSectionHeader(title: cashflowHistoryPrimaryTitle(for: transaction))

                            // Карточка операции
                            HistoryTransactionCard(
                                transaction: transaction,
                                viewModel: viewModel,
                                onOpenDetails: { selectedTransaction = transaction }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .coordinateSpace(name: "cashflowHistoryScroll")
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
            resetSummarySelectionAndPlaceholder()
        }
        .onChange(of: selectedStartDate) { _, _ in
            resetPagination()
            resetSummarySelectionAndPlaceholder()
        }
        .onChange(of: selectedEndDate) { _, _ in
            resetPagination()
            resetSummarySelectionAndPlaceholder()
        }
        .onChange(of: shouldShowSummary) { _, newValue in
            if !newValue {
                selectedSummaryCategoryRawValue = nil
                summaryCollapseProgress = 0
            }
        }
        .onPreferenceChange(CashflowHistorySummaryMinYPreferenceKey.self) { minY in
            summaryCollapseProgress = CashflowHistorySummaryLayout.collapseProgress(minY: minY)
        }
    }

    private var loadMoreButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedTransactionsLimit += Self.pageSize
            }
        } label: {
            Text(cashflowHistoryTr("cashflow.history.load_more"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(CashflowHistoryChrome.elevatedFill)
                )
                .overlay(
                    Capsule()
                        .stroke(CashflowHistoryChrome.subduedStroke, lineWidth: 0.9)
                )
        }
        .buttonStyle(.plain)
    }

    private var defaultDateRange: (start: Date, end: Date) {
        CashflowViewModel.defaultPeriodRange(referenceDate: Date(), calendar: .current)
    }

    private var isDateFilterCustomized: Bool {
        guard let selectedStartDate, let selectedEndDate else { return false }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(selectedStartDate, selectedEndDate))
        let end = calendar.startOfDay(for: max(selectedStartDate, selectedEndDate))
        return !calendar.isDate(start, inSameDayAs: defaultDateRange.start)
            || !calendar.isDate(end, inSameDayAs: defaultDateRange.end)
    }

    private var dateFilterTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("LLLL")
        switch (selectedStartDate, selectedEndDate) {
        case let (start?, end?):
            let normalizedStart = min(start, end)
            let normalizedEnd = max(start, end)
            if Calendar.current.isDate(
                normalizedStart,
                equalTo: normalizedEnd,
                toGranularity: .month
            ) {
                return formatter.string(from: normalizedStart).capitalized
            }
            formatter.setLocalizedDateFormatFromTemplate("dMMM")
            return "\(formatter.string(from: normalizedStart)) - \(formatter.string(from: normalizedEnd))"
        case let (start?, nil):
            return formatter.string(from: start).capitalized
        case let (nil, end?):
            return formatter.string(from: end).capitalized
        case (nil, nil):
            return cashflowHistoryTr("cashflow.history.period")
        }
    }

    private var selectedCardTitle: String? {
        guard let selectedCardID else { return nil }
        return viewModel.state.allCards.first(where: { $0.cardUniqueID == selectedCardID })?.name
    }

    private var summaryReloadKey: String {
        return [
            summaryMode.rawValue,
            selectedCardID ?? "all",
            "\(selectedFilterIndex)",
            isSearchActive ? searchText : "",
            cashflowHistoryTimeToken(for: selectedStartDate),
            cashflowHistoryTimeToken(for: selectedEndDate),
            "\(viewModel.state.transactions.count)",
            viewModel.state.displayCurrency
        ].joined(separator: "|")
    }

    private func resetPagination() {
        displayedTransactionsLimit = Self.pageSize
    }

    private func resetSummarySelectionAndPlaceholder() {
        selectedSummaryCategoryRawValue = nil
        summaryCollapseProgress = 0
        summaryModel = .empty(
            mode: summaryMode,
            currencyCode: viewModel.state.displayCurrency
        )
    }

    private func resetDateFilterToDefault() {
        let range = defaultDateRange
        selectedStartDate = range.start
        selectedEndDate = range.end
    }

    private func reloadSummary() async {
        let currentMode = summaryMode
        let model = await viewModel.historySummary(
            matching: summaryQuery,
            mode: currentMode
        )
        guard currentMode == summaryMode else { return }
        summaryModel = model
        if let selectedSummaryCategoryRawValue,
           !model.entries.contains(where: { $0.rawValue == selectedSummaryCategoryRawValue }) {
            self.selectedSummaryCategoryRawValue = nil
        }
    }

    private func matchesSelectedSummaryCategory(_ transaction: CashflowTransaction) -> Bool {
        guard let selectedSummaryCategoryRawValue else { return true }
        switch summaryMode {
        case .expense:
            return transaction.transactionType == .expense
                && (transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue) == selectedSummaryCategoryRawValue
        case .income:
            return transaction.transactionType == .income
                && (transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue) == selectedSummaryCategoryRawValue
        }
    }

    private var selectedFilterIndex: Int {
        CashflowHistoryTypeFilter.allCases.firstIndex(of: selectedFilter) ?? 0
    }

    private func formatSectionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("dMMMM y")
        return formatter.string(from: date)
    }
}

// MARK: - History Filter Chip

enum CashflowHistorySummaryPresentation {
    static func shouldShow(
        selectedFilter: CashflowHistoryTypeFilter,
        isSearchActive: Bool,
        searchText: String,
        entryCount: Int,
        totalAmount: Double
    ) -> Bool {
        guard totalAmount > 0, entryCount > 1 else { return false }
        guard !isSearchActive || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch selectedFilter {
        case .income, .expense:
            return true
        case .all, .transfer, .assetBalanceChange, .accountBalanceCorrection:
            return false
        }
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
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(chipForeground(isSelected: isSelected))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(chipBackground(isSelected: isSelected))
            .overlay(chipBorder(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryTypeFilterChip: View {
    let selectedFilter: CashflowHistoryTypeFilter
    let onSelect: (CashflowHistoryTypeFilter) -> Void
    let onReset: () -> Void

    private var isActive: Bool {
        selectedFilter != .all
    }

    var body: some View {
        if isActive {
            HStack(spacing: 8) {
                Menu {
                    ForEach(CashflowHistoryTypeFilter.allCases, id: \.self) { filter in
                        Button(filter.title) {
                            onSelect(filter)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedFilter.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(chipForeground(isSelected: true))
                    .padding(.leading, 18)
                    .padding(.trailing, 8)
                    .padding(.vertical, 11)
                }

                Button(action: onReset) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(chipForeground(isSelected: true))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
            }
            .background(chipBackground(isSelected: true))
            .overlay(chipBorder(isSelected: true))
        } else {
            Menu {
                ForEach(CashflowHistoryTypeFilter.allCases, id: \.self) { filter in
                    Button(filter.title) {
                        onSelect(filter)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedFilter.title)
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(chipForeground(isSelected: false))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(chipBackground(isSelected: false))
                .overlay(chipBorder(isSelected: false))
            }
        }
    }
}

private struct HistoryCardFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(chipForeground(isSelected: isSelected))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(chipBackground(isSelected: isSelected))
            .overlay(chipBorder(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

private func chipBackground(isSelected: Bool) -> some View {
    Capsule()
        .fill(isSelected ? CashflowHistoryChrome.selectionFill : CashflowHistoryChrome.quietFill)
}

private func chipBorder(isSelected: Bool) -> some View {
    Capsule()
        .stroke(
            isSelected ? CashflowHistoryChrome.selectionStroke : CashflowHistoryChrome.subduedStroke,
            lineWidth: 0.9
        )
}

private func chipForeground(isSelected: Bool) -> Color {
    AppColors.textPrimary
}

// MARK: - History Date Range Sheet

private struct HistoryDateRangeSheet: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    let resetToDefaultRange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftStartDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var draftEndDate: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                CalendarRangePickerPanel(
                    title: CalendarRangePickerCopy.sheetTitle(),
                    subtitle: cashflowHistoryTr("cashflow.custom_period.calendar_hint"),
                    startDate: $draftStartDate,
                    endDate: $draftEndDate,
                    theme: .cashflow
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom) {
                CalendarRangeSheetActionBar(
                    secondaryTitle: cashflowHistoryTr("cashflow.common.reset"),
                    primaryTitle: cashflowHistoryTr("cashflow.common.apply"),
                    theme: .cashflow
                ) {
                        resetToDefaultRange()
                        dismiss()
                } primaryAction: {
                        startDate = draftStartDate
                        endDate = draftEndDate
                        dismiss()
                }
            }
            .navigationTitle(cashflowHistoryTr("cashflow.history.date_filter.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassIconButton(
                        systemName: "xmark",
                        accessibilityLabel: cashflowHistoryTr("cashflow.common.dismiss")
                    ) {
                        dismiss()
                    }
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
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("dMMM y")
        let start = min(draftStartDate, draftEndDate)
        let end = max(draftStartDate, draftEndDate)
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

private struct HistoryCardFilterSheet: View {
    let cards: [Card]
    @Binding var selectedCardID: String?
    @Environment(\.dismiss) private var dismiss

    private var sortedCards: [Card] {
        cards.sorted { lhs, rhs in
            if lhs.archivedAt == nil && rhs.archivedAt != nil { return true }
            if lhs.archivedAt != nil && rhs.archivedAt == nil { return false }
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedCardID = nil
                    dismiss()
                } label: {
                    HStack {
                        Text(cashflowHistoryTr(
                            "cashflow.history.cards.all",
                            fallback: "Все счета и карты"
                        ))
                        Spacer()
                        if selectedCardID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(AppColors.textPrimary)

                ForEach(sortedCards, id: \.cardUniqueID) { card in
                    Button {
                        selectedCardID = card.cardUniqueID
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: card.cardType.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: card.cardColor ?? "47D7FF"))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.name)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(card.bank.displayName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            Spacer()

                            if selectedCardID == card.cardUniqueID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(cashflowHistoryTr("cashflow.history.cards", fallback: "Счета и карты"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(cashflowHistoryTr("cashflow.common.dismiss")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}

// MARK: - History Transaction Card

private struct HistoryTransactionDetailView: View {
    let transaction: CashflowTransaction
    @ObservedObject var viewModel: CashflowViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false

    private var cardNameByID: [String: String] {
        Dictionary(uniqueKeysWithValues: viewModel.state.allCards.map { ($0.cardUniqueID, $0.name) })
    }

    private var investmentNameByID: [String: String] {
        Dictionary(uniqueKeysWithValues: viewModel.state.availableInvestments.map { ($0.investmentUniqueID, $0.name) })
    }

    private var currentTransaction: CashflowTransaction {
        cashflowHistoryResolvedTransaction(for: transaction, in: viewModel.state.transactions)
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 14) {
                    detailCard
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(cashflowHistoryTr("cashflow.history.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(cashflowHistoryTr("cashflow.history.detail.delete.title"), isPresented: $showDeleteAlert) {
            Button(cashflowHistoryTr("cashflow.common.cancel"), role: .cancel) {}
            Button(cashflowHistoryTr("cashflow.history.detail.delete.with_recalc"), role: .destructive) {
                deleteTransaction(recalculate: true)
            }
            Button(cashflowHistoryTr("cashflow.history.detail.delete.without_recalc"), role: .destructive) {
                deleteTransaction(recalculate: false)
            }
        } message: {
            Text(cashflowHistoryTr("cashflow.history.detail.delete.message"))
        }
        .alert(
            cashflowHistoryTr(
                "cashflow.history.detail.delete.balance_update_failed.title",
                fallback: "Cannot update balances"
            ),
            isPresented: Binding(
                get: { viewModel.state.deleteBalanceUpdateErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.handle(.dismissDeleteBalanceUpdateError)
                    }
                }
            )
        ) {
            Button(cashflowHistoryTr("cashflow.common.ok"), role: .cancel) {
                viewModel.handle(.dismissDeleteBalanceUpdateError)
            }
        } message: {
            Text(viewModel.state.deleteBalanceUpdateErrorMessage ?? "")
        }
        .sheet(isPresented: $showEditSheet) {
            CashflowTransactionEditorView(
                viewModel: viewModel,
                transaction: currentTransaction,
                onSave: {
                    showEditSheet = false
                }
            )
        }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailRow(
                title: cashflowHistoryTr("cashflow.history.detail.amount"),
                value: formattedAmount
            )
            detailRow(
                title: cashflowHistoryTr("cashflow.history.detail.type"),
                value: cashflowHistoryPrimaryTitle(for: currentTransaction)
            )
            detailRow(
                title: cashflowHistoryTr("cashflow.history.detail.date"),
                value: formattedDate
            )

            if let category = categoryTitle {
                detailRow(
                    title: cashflowHistoryTr("cashflow.history.detail.category"),
                    value: category
                )
            }

            if let settlementAccountContext,
               let settlementCard = cardName(for: settlementAccountContext.cardID) {
                detailRow(
                    title: cashflowHistoryAccountLabel(
                        for: settlementAccountContext.direction,
                        transaction: currentTransaction
                    ),
                    value: settlementCard
                )
            }

            if let toCard = cardName(for: currentTransaction.toCardID) {
                detailRow(
                    title: cashflowHistoryTr("cashflow.history.detail.to_account"),
                    value: toCard
                )
            }

            if let investmentName = investmentName(for: currentTransaction.investmentID) {
                detailRow(
                    title: historyInvestmentTitle,
                    value: investmentName
                )
            }

            if let assetChangeDetails, !assetChangeDetails.isEmpty {
                detailRow(
                    title: historyChangesTitle,
                    value: assetChangeDetails
                )
            }

            if let note = detailNote {
                detailRow(
                    title: cashflowHistoryTr("cashflow.history.detail.note"),
                    value: note
                )
            }
        }
        .padding(18)
        .background {
            CashflowHistorySurfaceBackground(
                cornerRadius: CashflowHistoryChrome.rowCornerRadius,
                isElevated: true
            )
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                showEditSheet = true
            } label: {
                Label(cashflowHistoryTr("cashflow.history.detail.edit"), systemImage: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(CashflowHistoryChrome.elevatedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(CashflowHistoryChrome.subduedStroke, lineWidth: 0.9)
                            )
                    )
            }
            .buttonStyle(.plain)

            Button {
                showDeleteAlert = true
            } label: {
                Label(cashflowHistoryTr("cashflow.history.detail.delete"), systemImage: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.95))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.red.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.red.opacity(0.36), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM y, HH:mm")
        return formatter.string(from: currentTransaction.transactionDate)
    }

    private var categoryTitle: String? {
        switch currentTransaction.transactionType {
        case .income:
            return viewModel.incomeCategoryDisplayName(for: currentTransaction.incomeCategoryRaw)
        case .expense:
            return viewModel.expenseCategoryDisplayName(for: currentTransaction.expenseCategoryRaw)
        case .transfer, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return nil
        }
    }

    private var formattedAmount: String {
        let amount = cashflowHistoryAmountText(currentTransaction.amount)
        return "\(amount) \(resolvedCurrencyCode)"
    }

    private var resolvedCurrencyCode: String {
        let rawCurrency = currentTransaction.currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !rawCurrency.isEmpty {
            return rawCurrency
        }
        return viewModel.state.displayCurrency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func cardName(for cardID: String?) -> String? {
        guard let cardID, let name = cardNameByID[cardID], !name.isEmpty else { return nil }
        return name
    }

    private func investmentName(for investmentID: String?) -> String? {
        guard let investmentID,
              let name = investmentNameByID[investmentID],
              !name.isEmpty else { return nil }
        return name
    }

    private var assetChangeDetails: String? {
        cashflowHistoryAssetChangeSummary(
            for: currentTransaction,
            currencyCode: resolvedCurrencyCode
        )
    }

    private var detailNote: String? {
        let note = currentTransaction.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !note.isEmpty else { return nil }
        return note == cashflowHistoryPrimaryTitle(for: currentTransaction) ? nil : note
    }

    private var settlementAccountContext: CashflowHistorySettlementAccountContext? {
        cashflowHistorySettlementAccountContext(
            for: currentTransaction,
            in: viewModel.state.transactions
        )
    }

    private var historyInvestmentTitle: String {
        AppLocalization.string(
            "finances.account.type.investment",
            locale: AppLocalization.currentAppLocale
        )
    }

    private var historyChangesTitle: String {
        AppLocalization.string(
            "cashflow.history.detail.changes",
            locale: AppLocalization.currentAppLocale,
            fallback: "What changed"
        )
    }

    private func deleteTransaction(recalculate: Bool) {
        viewModel.handle(.deleteTransaction(currentTransaction, recalculate: recalculate))
        dismiss()
    }
}

private struct HistoryTransactionCard: View {
    let transaction: CashflowTransaction
    @ObservedObject var viewModel: CashflowViewModel
    let onOpenDetails: () -> Void

    var body: some View {
        Button {
            onOpenDetails()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(formattedAmount)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)

                if let description = transactionDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                CashflowHistorySurfaceBackground(
                    cornerRadius: CashflowHistoryChrome.rowCornerRadius,
                    isElevated: false
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Форматирование суммы

    private var formattedAmount: String {
        let amountStr = cashflowHistoryAmountText(transaction.amount)
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
        cashflowHistoryDescription(
            for: transaction,
            relatedTransactions: viewModel.state.transactions,
            cardNameResolver: cardName(for:),
            investmentNameResolver: investmentName(for:),
            incomeCategoryResolver: viewModel.incomeCategoryDisplayName(for:),
            expenseCategoryResolver: viewModel.expenseCategoryDisplayName(for:)
        )
    }

    private func cardName(for cardID: String?) -> String? {
        guard let cardID else { return nil }
        return viewModel.state.allCards.first(where: { $0.cardUniqueID == cardID })?.name
    }

    private func investmentName(for investmentID: String?) -> String? {
        guard let investmentID else { return nil }
        return viewModel.state.availableInvestments.first(where: { $0.investmentUniqueID == investmentID })?.name
    }

    private var assetChangeSummary: String? {
        cashflowHistoryAssetChangeSummary(
            for: transaction,
            currencyCode: resolvedCurrencyCode
        )
    }
}
