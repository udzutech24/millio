//
//  CashflowTransactionEditorView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

struct CashflowTransactionEditorView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let transactionType: CashflowTransactionType?
    let editingTransaction: CashflowTransaction?

    @State private var selectedTransactionType: CashflowTransactionType
    @State private var amountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var transactionDate: Date = Date()
    @State private var selectedCardID: String? = nil
    @State private var selectedToCardID: String? = nil
    @State private var selectedIncomeCategory: IncomeCategory? = nil
    @State private var selectedExpenseCategory: ExpenseCategory? = nil
    @State private var note: String = ""
    @State private var availableCurrencies: [String] = []
    @State private var isLoadingCurrencies: Bool = false
    @State private var isAmountOverBalance: Bool = false
    @State private var validationTask: Task<Void, Never>? = nil
    
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""

    init(viewModel: CashflowViewModel, transactionType: CashflowTransactionType? = nil, transaction: CashflowTransaction? = nil) {
        self.viewModel = viewModel
        self.transactionType = transactionType
        self.editingTransaction = transaction

        if let transaction = transaction {
            _selectedTransactionType = State(initialValue: transaction.transactionType)
            _amountText = State(initialValue: formatNumberForDisplay(transaction.amount))
            _selectedCurrency = State(initialValue: transaction.currency)
            _transactionDate = State(initialValue: transaction.transactionDate)
            _selectedCardID = State(initialValue: transaction.cardID)
            _selectedToCardID = State(initialValue: transaction.toCardID)
            _selectedIncomeCategory = State(initialValue: transaction.incomeCategory)
            _selectedExpenseCategory = State(initialValue: transaction.expenseCategory)
            _note = State(initialValue: transaction.note ?? "")
        } else if let type = transactionType {
            _selectedTransactionType = State(initialValue: type)
            if type == .income {
                _selectedIncomeCategory = State(initialValue: .salary)
            } else if type == .expense {
                _selectedExpenseCategory = State(initialValue: .groceries)
            }
        } else {
            _selectedTransactionType = State(initialValue: .expense)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        // Тип транзакции (только для новых)
                        if editingTransaction == nil {
                            transactionTypeSection
                        }

                        // Категория
                        if selectedTransactionType == .income || selectedTransactionType == .expense {
                            categorySection
                        }

                        mainInfoSection
                        cardSection
                        additionalSection
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle(editingTransaction == nil ? "Новая операция" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveTransaction()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: getGradientColors(),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }
            }
            .onAppear {
                loadAvailableCurrencies()
                if selectedCardID == nil && !viewModel.state.availableCards.isEmpty {
                    selectedCardID = viewModel.state.availableCards.first?.cardUniqueID
                }
                validateAvailableBalance()
            }
            .onChange(of: selectedCardID) { _, _ in
                if selectedCardID == selectedToCardID {
                    selectedToCardID = nil
                }
                validateAvailableBalance()
            }
            .onChange(of: selectedToCardID) { _, _ in
                if selectedToCardID == selectedCardID {
                    selectedToCardID = nil
                }
            }
            .onChange(of: selectedCurrency) { _, _ in
                validateAvailableBalance()
            }
            .onChange(of: amountText) { _, _ in
                validateAvailableBalance()
            }
            .onChange(of: transactionDate) { _, _ in
                validateAvailableBalance()
            }
            .onChange(of: selectedTransactionType) { _, _ in
                validateAvailableBalance()
            }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    CurrencyPickerView(
                        allCodes: CurrencySelectionSupport.allCodes(includeCrypto: true),
                        searchText: $currencySearchText,
                        selectedCodes: [],
                        favoriteCodes: [],
                        currentSelection: selectedCurrency,
                        onToggleFavorite: nil,
                        onSelect: { currency in
                            selectedCurrency = currency
                            showCurrencyPicker = false
                        }
                    )
                    .navigationTitle("Валюта операции")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") {
                                showCurrencyPicker = false
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Тип операции

    private var transactionTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Тип операции")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Тип операции")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker("Тип операции", selection: $selectedTransactionType) {
                            ForEach(CashflowTransactionType.allCases, id: \.self) { type in
                                HStack(spacing: 6) {
                                    Image(systemName: type.icon)
                                        .font(.system(size: 12))
                                    Text(type.displayName)
                                }
                                .tag(type)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                }
            }
            .onChange(of: selectedTransactionType) { oldValue, newValue in
                if newValue == .income {
                    selectedIncomeCategory = .salary
                    selectedExpenseCategory = nil
                } else if newValue == .expense {
                    selectedExpenseCategory = .groceries
                    selectedIncomeCategory = nil
                } else {
                    selectedIncomeCategory = nil
                    selectedExpenseCategory = nil
                }
            }
        }
    }

    // MARK: - Категория

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Категория")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    if selectedTransactionType == .income {
                        HStack {
                            Text("Категория дохода")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Picker("Категория дохода", selection: Binding(
                                get: { selectedIncomeCategory ?? .salary },
                                set: { selectedIncomeCategory = $0 }
                            )) {
                                ForEach(IncomeCategory.allCases, id: \.self) { category in
                                    HStack(spacing: 6) {
                                        Image(systemName: category.icon)
                                            .font(.system(size: 12))
                                        Text(category.displayName)
                                    }
                                    .tag(category)
                                }
                            }
                            .tint(AppColors.textTertiary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    } else if selectedTransactionType == .expense {
                        HStack {
                            Text("Категория расхода")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Picker("Категория расхода", selection: Binding(
                                get: { selectedExpenseCategory ?? .groceries },
                                set: { selectedExpenseCategory = $0 }
                            )) {
                                ForEach(ExpenseCategory.allCases, id: \.self) { category in
                                    HStack(spacing: 6) {
                                        Image(systemName: category.icon)
                                            .font(.system(size: 12))
                                        Text(category.displayName)
                                    }
                                    .tag(category)
                                }
                            }
                            .tint(AppColors.textTertiary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: - Основная информация

    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Основная информация")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Сумма")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                amountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: 150)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    HStack {
                        Text("Валюта")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if isLoadingCurrencies {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AppColors.textTertiary)
                        } else {
                            Button {
                                showCurrencyPicker = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedCurrency)
                                        .font(.system(size: 17))
                                        .foregroundStyle(AppColors.textPrimary)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    HStack {
                        Text("Дата")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        DatePicker("", selection: $transactionDate, displayedComponents: .date)
                            .labelsHidden()
                            .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Карта

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if selectedTransactionType == .transfer {
                FinancesSectionHeader(title: "Перевод")
            } else {
                FinancesSectionHeader(title: "Карта")
            }

            FinancesGlassCard {
                VStack(spacing: 0) {
                    if selectedTransactionType == .income || selectedTransactionType == .expense {
                        incomeExpenseCardContent
                    } else if selectedTransactionType == .transfer {
                        transferCardContent
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var incomeExpenseCardContent: some View {
        if viewModel.state.availableCards.isEmpty {
            Text("Нет доступных карт")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
        } else {
            HStack {
                Text("Карта")
                    .foregroundStyle(AppColors.textPrimary)
                    .layoutPriority(1)
                Spacer()
                Picker("Карта", selection: Binding(
                    get: { selectedCardID ?? "" },
                    set: { selectedCardID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Выберите карту").tag("")
                    ForEach(viewModel.state.availableCards) { card in
                        Text(card.name).tag(card.cardUniqueID)
                    }
                }
                .tint(AppColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)

            if shouldValidateBalance, let availableText = availableBalanceText {
                FinancesRowDivider()
                Text(availableText)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
            }

            if isAmountOverBalance {
                FinancesRowDivider()
                Text("Недостаточно средств")
                    .font(.caption)
                    .foregroundStyle(AppColors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var transferCardContent: some View {
        if viewModel.state.availableCards.isEmpty {
            Text("Нет доступных карт")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
        } else {
            HStack {
                Text("С карты")
                    .foregroundStyle(AppColors.textPrimary)
                    .layoutPriority(1)
                Spacer()
                Picker("С карты", selection: Binding(
                    get: { selectedCardID ?? "" },
                    set: { selectedCardID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Выберите карту").tag("")
                    ForEach(viewModel.state.availableCards.filter { $0.cardUniqueID != selectedToCardID }) { card in
                        Text(card.name).tag(card.cardUniqueID)
                    }
                }
                .tint(AppColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)

            if shouldValidateBalance, let availableText = availableBalanceText {
                FinancesRowDivider()
                Text(availableText)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
            }

            if isAmountOverBalance {
                FinancesRowDivider()
                Text("Недостаточно средств")
                    .font(.caption)
                    .foregroundStyle(AppColors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
            }

            FinancesRowDivider()

            HStack {
                Text("На карту")
                    .foregroundStyle(AppColors.textPrimary)
                    .layoutPriority(1)
                Spacer()
                Picker("На карту", selection: Binding(
                    get: { selectedToCardID ?? "" },
                    set: { selectedToCardID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Выберите карту").tag("")
                    ForEach(viewModel.state.availableCards.filter { $0.cardUniqueID != selectedCardID }) { card in
                        Text(card.name).tag(card.cardUniqueID)
                    }
                }
                .tint(AppColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Дополнительно

    private var additionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Дополнительно")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    TextField("Комментарий", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        guard !amountText.isEmpty,
              let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            return false
        }

        switch selectedTransactionType {
        case .income, .expense:
            return selectedCardID != nil && !isAmountOverBalance
        case .transfer:
            return selectedCardID != nil && selectedToCardID != nil && selectedCardID != selectedToCardID && !isAmountOverBalance
        case .balanceAdjustment, .cardBalanceAdjustment:
            return selectedCardID != nil || editingTransaction?.creditID != nil || editingTransaction?.investmentID != nil
        case .creditDebtAdjustment:
            return selectedCardID != nil || editingTransaction?.creditID != nil
        }
    }

    private func getGradientColors() -> [Color] {
        switch selectedTransactionType {
        case .income:
            return AppColors.incomeGradient
        case .expense:
            return AppColors.expenseGradient
        case .transfer:
            return AppColors.cashflowGradient
        case .balanceAdjustment:
            return AppColors.cardIndexGradient
        case .cardBalanceAdjustment:
            return AppColors.cardIndexGradient
        case .creditDebtAdjustment:
            return AppColors.creditsGradient
        }
    }

    // MARK: - Save

    private func saveTransaction() {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            return
        }

        let transaction: CashflowTransaction
        if let editing = editingTransaction {
            transaction = editing
        } else {
            transaction = CashflowTransaction(
                transactionType: selectedTransactionType,
                amount: amount,
                currency: selectedCurrency,
                transactionDate: transactionDate,
                cardID: selectedCardID,
                toCardID: selectedToCardID,
                incomeCategory: selectedIncomeCategory,
                expenseCategory: selectedExpenseCategory,
                note: note.isEmpty ? nil : note
            )
        }

        transaction.transactionTypeRaw = selectedTransactionType.rawValue
        transaction.amount = amount
        transaction.currency = selectedCurrency
        transaction.transactionDate = transactionDate
        transaction.cardID = selectedCardID
        transaction.toCardID = selectedToCardID
        transaction.incomeCategoryRaw = selectedIncomeCategory?.rawValue
        transaction.expenseCategoryRaw = selectedExpenseCategory?.rawValue
        transaction.note = note.isEmpty ? nil : note

        viewModel.handle(.updateTransaction(transaction))
        dismiss()
    }

    // MARK: - Currency Loading

    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }

            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())

            var currencies = Array(fromRateSource)
            if !currencies.contains(selectedCurrency) {
                currencies.append(selectedCurrency)
            }
            availableCurrencies = currencies.sorted()
        }
    }

    // MARK: - Number Formatting

    private func formatNumberForDisplay(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formatNumberForDisplay(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        let normalized = value.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        if let doubleValue = Double(normalized) {
            return formatNumberForDisplay(doubleValue)
        }

        return value
    }

    // MARK: - Balance Validation

    private var shouldValidateBalance: Bool {
        selectedTransactionType == .expense || selectedTransactionType == .transfer
    }

    private var availableBalanceText: String? {
        guard shouldValidateBalance,
              let cardID = selectedCardID,
              let card = viewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID }) else {
            return nil
        }

        let formatted = formatNumberForDisplay(card.balance)
        return "Доступно: \(formatted) \(card.currency)"
    }

    private func parseAmount() -> Double? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func validateAvailableBalance() {
        guard shouldValidateBalance,
              let cardID = selectedCardID,
              let amount = parseAmount(),
              amount > 0 else {
            isAmountOverBalance = false
            return
        }

        let currency = selectedCurrency
        let card = cardID
        let date = transactionDate

        validationTask?.cancel()
        validationTask = Task {
            do {
                let isAvailable = try await viewModel.isAmountAvailable(
                    amount: amount,
                    currency: currency,
                    fromCardID: card,
                    on: date
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isAmountOverBalance = !isAvailable
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isAmountOverBalance = false
                }
            }
            validationTask = nil
        }
    }
}
