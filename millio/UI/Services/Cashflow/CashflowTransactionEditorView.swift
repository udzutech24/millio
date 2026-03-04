//
//  CashflowTransactionEditorView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData
import UIKit

struct CashflowTransactionEditorView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss

    let transactionType: CashflowTransactionType?
    let editingTransaction: CashflowTransaction?
    let showsTransactionTypeSection: Bool
    let showsCategorySection: Bool
    let showsRecurrenceSection: Bool
    let wrapsInNavigationStack: Bool
    let showsDismissButton: Bool
    let customNavigationTitle: String?
    let preselectedIncomeCategoryRaw: String?
    let preselectedExpenseCategoryRaw: String?
    let onSave: (() -> Void)?

    @State private var selectedTransactionType: CashflowTransactionType
    @State private var amountText: String = ""
    @State private var amountDisplayText: String = ""
    @State private var selectedCurrency: String = SettingsManager.shared.primaryCurrencyCode
    @State private var transactionDate: Date = Date()
    @State private var selectedCardID: String? = nil
    @State private var selectedToCardID: String? = nil
    @State private var selectedIncomeCategoryRaw: String? = nil
    @State private var selectedExpenseCategoryRaw: String? = nil
    @State private var note: String = ""
    @State private var recurrenceRule: CashflowRecurrenceRule = .none
    @State private var availableCurrencies: [String] = []
    @State private var isLoadingCurrencies: Bool = false
    @State private var isAmountOverBalance: Bool = false
    @State private var validationTask: Task<Void, Never>? = nil
    
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    @State private var showCategorySheet: Bool = false
    @FocusState private var isAmountFieldFocused: Bool

    private let primarySecondaryText = Color.white.opacity(0.78)
    private let innerGlassFill = Color.white.opacity(0.022)

    init(
        viewModel: CashflowViewModel,
        transactionType: CashflowTransactionType? = nil,
        transaction: CashflowTransaction? = nil,
        showsTransactionTypeSection: Bool = true,
        showsCategorySection: Bool = true,
        showsRecurrenceSection: Bool = true,
        wrapsInNavigationStack: Bool = true,
        showsDismissButton: Bool = true,
        customNavigationTitle: String? = nil,
        preselectedIncomeCategoryRaw: String? = nil,
        preselectedExpenseCategoryRaw: String? = nil,
        initialRecurrenceRule: CashflowRecurrenceRule? = nil,
        onSave: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.transactionType = transactionType
        self.editingTransaction = transaction
        self.showsTransactionTypeSection = showsTransactionTypeSection
        self.showsCategorySection = showsCategorySection
        self.showsRecurrenceSection = showsRecurrenceSection
        self.wrapsInNavigationStack = wrapsInNavigationStack
        self.showsDismissButton = showsDismissButton
        self.customNavigationTitle = customNavigationTitle
        self.preselectedIncomeCategoryRaw = preselectedIncomeCategoryRaw
        self.preselectedExpenseCategoryRaw = preselectedExpenseCategoryRaw
        self.onSave = onSave

        if let transaction = transaction {
            _selectedTransactionType = State(initialValue: transaction.transactionType)
            _amountText = State(initialValue: AmountInputFormatter.plainString(from: transaction.amount))
            _selectedCurrency = State(initialValue: transaction.currency)
            _transactionDate = State(initialValue: transaction.transactionDate)
            _selectedCardID = State(initialValue: transaction.cardID)
            _selectedToCardID = State(initialValue: transaction.toCardID)
            _selectedIncomeCategoryRaw = State(initialValue: transaction.incomeCategoryRaw)
            _selectedExpenseCategoryRaw = State(initialValue: transaction.expenseCategoryRaw)
            _note = State(initialValue: transaction.note ?? "")
            _recurrenceRule = State(initialValue: transaction.recurrenceRule)
        } else if let type = transactionType {
            _selectedTransactionType = State(initialValue: type)
            if type == .income {
                _selectedIncomeCategoryRaw = State(initialValue: preselectedIncomeCategoryRaw ?? IncomeCategory.salary.rawValue)
            } else if type == .expense {
                _selectedExpenseCategoryRaw = State(initialValue: preselectedExpenseCategoryRaw ?? ExpenseCategory.groceries.rawValue)
            }
            _recurrenceRule = State(initialValue: initialRecurrenceRule ?? .none)
        } else {
            _selectedTransactionType = State(initialValue: .expense)
            _recurrenceRule = State(initialValue: initialRecurrenceRule ?? .none)
        }
    }

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack {
                    editorContent
                }
            } else {
                editorContent
            }
        }
    }

    private var editorContent: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if editingTransaction == nil && showsTransactionTypeSection {
                        transactionTypeSection
                    }

                    if showsCategorySection && (selectedTransactionType == .income || selectedTransactionType == .expense) {
                        categorySection
                    }

                    if shouldShowSelectedCategorySummary {
                        selectedCategorySummarySection
                    }

                    mainInfoSection
                    if showsRecurrenceSection && (selectedTransactionType == .income || selectedTransactionType == .expense) {
                        recurrenceSection
                    }
                    additionalSection
                }
                .padding(.top, 14)
                .padding(.bottom, 40)
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .dismissKeyboardOnTap()
        }
        .navigationTitle(resolvedNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        fireLightImpact()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .buttonStyle(.plain)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    fireLightImpact()
                    saveTransaction()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isValid ? Color(hex: "6DFFC7") : AppColors.textSecondary.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .disabled(!isValid)
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            loadAvailableCurrencies()
            synchronizeSelectedCards()
            if editingTransaction == nil,
               selectedTransactionType == .income,
               selectedIncomeCategoryRaw == nil {
                selectedIncomeCategoryRaw = preselectedIncomeCategoryRaw ?? IncomeCategory.salary.rawValue
            }
            if editingTransaction == nil,
               selectedTransactionType == .expense,
               selectedExpenseCategoryRaw == nil {
                selectedExpenseCategoryRaw = preselectedExpenseCategoryRaw ?? ExpenseCategory.groceries.rawValue
            }
            validateAvailableBalance()
            if amountDisplayText.isEmpty {
                amountDisplayText = AmountInputFormatter.display(amountText, maxFractionDigits: 0)
            }
            DispatchQueue.main.async {
                isAmountFieldFocused = true
            }
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
            synchronizeSelectedCards()
            validateAvailableBalance()
        }
        .onChange(of: amountText) { _, _ in
            validateAvailableBalance()
        }
        .onChange(of: amountDisplayText) { _, newValue in
            let sanitized = AmountInputFormatter.sanitize(newValue, maxFractionDigits: 0)
            let formatted = AmountInputFormatter.display(sanitized, maxFractionDigits: 0)
            if newValue != formatted {
                amountDisplayText = formatted
            }
            if amountText != sanitized {
                amountText = sanitized
            }
        }
        .onChange(of: transactionDate) { _, _ in
            validateAvailableBalance()
        }
        .onChange(of: selectedTransactionType) { _, _ in
            synchronizeSelectedCards()
            validateAvailableBalance()
        }
        .onChange(of: viewModel.state.availableCards.map(\.cardUniqueID)) { _, _ in
            synchronizeSelectedCards()
            validateAvailableBalance()
        }
        .sheet(isPresented: $showCategorySheet) {
            CashflowCategorySelectionSheet(
                viewModel: viewModel,
                kind: selectedCategoryKind,
                selectedRaw: selectedCategoryRawBinding
            )
        }
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
                CurrencyPickerView(
                    allCodes: CurrencySelectionSupport.allCodes(includeCrypto: true),
                    searchText: $currencySearchText,
                    selectedCodes: favoriteCodes,
                    favoriteCodes: Set(favoriteCodes),
                    currentSelection: selectedCurrency,
                    primaryPinnedCode: Self.operationCurrencyPrimaryPinnedCode(
                        from: SettingsManager.shared.primaryCurrencyCode
                    ),
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var resolvedNavigationTitle: String {
        if let customNavigationTitle {
            return customNavigationTitle
        }
        return editingTransaction == nil ? "Новая операция" : "Редактировать"
    }

    // MARK: - Тип операции

    private var transactionTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Тип операции")
            editorCard {
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
                    selectedIncomeCategoryRaw = selectedIncomeCategoryRaw ?? IncomeCategory.salary.rawValue
                    selectedExpenseCategoryRaw = nil
                } else if newValue == .expense {
                    selectedExpenseCategoryRaw = selectedExpenseCategoryRaw ?? ExpenseCategory.groceries.rawValue
                    selectedIncomeCategoryRaw = nil
                } else {
                    selectedIncomeCategoryRaw = nil
                    selectedExpenseCategoryRaw = nil
                    recurrenceRule = .none
                }
            }
        }
    }

    // MARK: - Категория

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Категория")
            editorCard {
                Button {
                    fireLightImpact()
                    showCategorySheet = true
                } label: {
                    HStack {
                        Text(selectedTransactionType == .income ? "Категория дохода" : "Категория расхода")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        HStack(spacing: 8) {
                            CashflowCategoryIconView(
                                icon: selectedCategoryOption.icon,
                                fontSize: 14,
                                fontWeight: .semibold,
                                tint: AnyShapeStyle(AppColors.textSecondary)
                            )
                            Text(selectedCategoryOption.displayName)
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Основная информация

    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Основная информация")
            editorCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Сумма")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { amountDisplayText },
                            set: { amountDisplayText = $0 }
                        ))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .focused($isAmountFieldFocused)
                        .frame(maxWidth: 150)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: getGradientColors(),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ).opacity(0.55),
                                        lineWidth: 1
                                    )
                            )
                    )

                    if shouldShowCardSelectionInMainInfo {
                        FinancesRowDivider()
                        mainInfoCardRows
                        FinancesRowDivider()
                    } else {
                        FinancesRowDivider()
                    }

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

    private var selectedCategorySummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(selectedTransactionType == .income ? "Выбранный доход" : "Выбранный расход")
            editorCard {
                HStack(spacing: 10) {
                    CashflowCategoryIconView(
                        icon: selectedCategoryOption.icon,
                        fontSize: 14,
                        fontWeight: .semibold,
                        tint: AnyShapeStyle(AppColors.textSecondary)
                    )
                    .frame(width: 20)
                    Text(selectedCategoryOption.displayName)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
        }
    }

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Повтор")
            editorCard {
                HStack {
                    Text("Частота")
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Picker("Частота", selection: $recurrenceRule) {
                        ForEach(CashflowRecurrenceRule.allCases, id: \.self) { rule in
                            Text(rule.displayName).tag(rule)
                        }
                    }
                    .tint(AppColors.textTertiary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var mainInfoCardRows: some View {
        if selectedTransactionType == .income || selectedTransactionType == .expense {
            incomeExpenseCardContent
        } else if selectedTransactionType == .transfer {
            transferCardContent
        }
    }

    @ViewBuilder
    private var incomeExpenseCardContent: some View {
        if cardsForCurrentSelection.isEmpty {
            Text("Нет карт в выбранной валюте")
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
                    ForEach(cardsForCurrentSelection) { card in
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
            sectionTitle("Дополнительно")
            editorCard {
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

    private var selectedCategoryKind: CashflowCategoryKind {
        selectedTransactionType == .income ? .income : .expense
    }

    private var selectedCategoryRawBinding: Binding<String> {
        Binding(
            get: {
                if selectedCategoryKind == .income {
                    return selectedIncomeCategoryRaw ?? IncomeCategory.salary.rawValue
                }
                return selectedExpenseCategoryRaw ?? ExpenseCategory.groceries.rawValue
            },
            set: { newValue in
                if selectedCategoryKind == .income {
                    selectedIncomeCategoryRaw = newValue
                } else {
                    selectedExpenseCategoryRaw = newValue
                }
            }
        )
    }

    private var shouldShowSelectedCategorySummary: Bool {
        !showsCategorySection && (selectedTransactionType == .income || selectedTransactionType == .expense)
    }

    private var shouldShowCardSelectionInMainInfo: Bool {
        Self.mainInfoRows(for: selectedTransactionType).contains(.fromCard)
    }

    private var cardsForCurrentSelection: [Card] {
        Self.cardsForCurrency(
            viewModel.state.availableCards,
            transactionType: selectedTransactionType,
            currency: selectedCurrency
        )
    }

    private var selectedCategoryOption: CashflowCategoryOption {
        let kind = selectedCategoryKind
        let fallbackRaw = kind == .income ? IncomeCategory.salary.rawValue : ExpenseCategory.groceries.rawValue
        let raw: String
        if kind == .income {
            raw = selectedIncomeCategoryRaw ?? fallbackRaw
        } else {
            raw = selectedExpenseCategoryRaw ?? fallbackRaw
        }
        return viewModel.categoryOption(for: raw, kind: kind)
    }

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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(primarySecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func fireLightImpact() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.9)
    }

    private func fireSuccessHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(innerGlassFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: getGradientColors(),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ).opacity(0.45),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.25))
                    )
                    .shadow(color: getGradientColors().first?.opacity(0.10) ?? .clear, radius: 6, x: 0, y: 0)
            )
    }

    // MARK: - Save

    private func saveTransaction() {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            return
        }

        let resolvedIncomeCategoryRaw: String? = selectedTransactionType == .income
            ? (selectedIncomeCategoryRaw ?? IncomeCategory.salary.rawValue)
            : nil
        let resolvedExpenseCategoryRaw: String? = selectedTransactionType == .expense
            ? (selectedExpenseCategoryRaw ?? ExpenseCategory.groceries.rawValue)
            : nil
        let effectiveRecurrenceRule: CashflowRecurrenceRule = showsRecurrenceSection ? recurrenceRule : .none
        let resolvedRecurrenceSeriesID: String? = {
            if effectiveRecurrenceRule == .none {
                if editingTransaction?.isRecurringTemplate == true {
                    return nil
                }
                return editingTransaction?.recurrenceSeriesID
            }
            return editingTransaction?.recurrenceSeriesID ?? UUID().uuidString
        }()

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
                incomeCategoryRaw: resolvedIncomeCategoryRaw,
                expenseCategoryRaw: resolvedExpenseCategoryRaw,
                note: note.isEmpty ? nil : note,
                recurrenceRule: effectiveRecurrenceRule,
                recurrenceSeriesID: resolvedRecurrenceSeriesID
            )
        }

        transaction.transactionTypeRaw = selectedTransactionType.rawValue
        transaction.amount = amount
        transaction.currency = selectedCurrency
        transaction.transactionDate = transactionDate
        transaction.cardID = selectedCardID
        transaction.toCardID = selectedToCardID
        transaction.incomeCategoryRaw = resolvedIncomeCategoryRaw
        transaction.expenseCategoryRaw = resolvedExpenseCategoryRaw
        transaction.note = note.isEmpty ? nil : note
        transaction.recurrenceRuleRaw = effectiveRecurrenceRule.rawValue
        transaction.recurrenceSeriesID = resolvedRecurrenceSeriesID

        viewModel.handle(.updateTransaction(transaction))
        fireSuccessHaptic()
        if let onSave {
            onSave()
        } else {
            dismiss()
        }
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
        AmountInputFormatter.display(String(value))
    }

    private func formatNumberForDisplay(_ value: String) -> String {
        AmountInputFormatter.display(value)
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
        AmountInputFormatter.parse(amountText)
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

    private func synchronizeSelectedCards() {
        let selectableCards = cardsForCurrentSelection
        let selectableIDs = Set(selectableCards.map(\.cardUniqueID))

        if let selectedCardID, !selectableIDs.contains(selectedCardID) {
            self.selectedCardID = nil
        }

        if selectedTransactionType == .transfer {
            if selectedCardID == nil && !selectableCards.isEmpty {
                selectedCardID = selectableCards.first?.cardUniqueID
            }
            if selectedToCardID == selectedCardID {
                selectedToCardID = nil
            }
            return
        }

        if selectedCardID == nil {
            selectedCardID = selectableCards.first?.cardUniqueID
        }
        selectedToCardID = nil
    }
}

enum CashflowEditorMainInfoRow: Equatable {
    case amount
    case fromCard
    case toCard
    case currency
    case date
}

extension CashflowTransactionEditorView {
    static func operationCurrencyPrimaryPinnedCode(from primaryCurrencyCode: String?) -> String? {
        guard let primaryCurrencyCode else { return nil }
        let normalized = primaryCurrencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func mainInfoRows(for transactionType: CashflowTransactionType) -> [CashflowEditorMainInfoRow] {
        switch transactionType {
        case .income, .expense:
            return [.amount, .fromCard, .currency, .date]
        case .transfer:
            return [.amount, .fromCard, .toCard, .currency, .date]
        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return [.amount, .currency, .date]
        }
    }

    static func cardsForCurrency(
        _ cards: [Card],
        transactionType: CashflowTransactionType,
        currency: String
    ) -> [Card] {
        guard transactionType == .income || transactionType == .expense else {
            return cards
        }

        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCurrency.isEmpty else {
            return cards
        }

        return cards.filter {
            $0.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCurrency
        }
    }
}

enum CashflowCategoryEditorMode {
    case create
    case edit(rawValue: String)
}

private struct CashflowCategorySelectionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryKind
    @Binding var selectedRaw: String

    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var showEditorSheet: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var editorMode: CashflowCategoryEditorMode = .create
    @State private var editorName: String = ""
    @State private var editorIcon: String = CashflowCustomCategory.defaultIcon
    @State private var pendingDeleteRaw: String?

    private var title: String {
        kind == .income ? "Категории доходов" : "Категории расходов"
    }

    private var createButtonTitle: String {
        kind == .income ? "Создать категорию дохода" : "Создать категорию расхода"
    }

    private var options: [CashflowCategoryOption] {
        viewModel.categoryOptions(for: kind, matching: searchText)
    }

    private var fallbackRaw: String {
        kind == .income ? IncomeCategory.other.rawValue : ExpenseCategory.other.rawValue
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                            TextField("Поиск категории", text: $searchText)
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

                        FinancesGlassCard {
                            VStack(spacing: 0) {
                                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                    Button {
                                        selectedRaw = option.rawValue
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 10) {
                                            CashflowCategoryIconView(
                                                icon: option.icon,
                                                fontSize: 14,
                                                fontWeight: .semibold,
                                                tint: AnyShapeStyle(AppColors.textSecondary)
                                            )
                                            .frame(width: 20)
                                            Text(option.displayName)
                                                .foregroundStyle(AppColors.textPrimary)
                                            Spacer()
                                            if option.rawValue == selectedRaw {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(AppColors.textPrimary)
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 14)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Редактировать") {
                                            openEditSheet(for: option)
                                        }
                                        if viewModel.canDeleteCategory(rawValue: option.rawValue, kind: kind) {
                                            Button("Удалить", role: .destructive) {
                                                pendingDeleteRaw = option.rawValue
                                                showDeleteAlert = true
                                            }
                                        }
                                    }

                                    if index < options.count - 1 {
                                        FinancesRowDivider()
                                    }
                                }
                            }
                        }

                        Button {
                            openCreateSheet()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(createButtonTitle)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
            .alert("Удалить категорию?", isPresented: $showDeleteAlert) {
                Button("Отмена", role: .cancel) {
                    pendingDeleteRaw = nil
                }
                Button("Удалить", role: .destructive) {
                    guard let raw = pendingDeleteRaw else { return }
                    if viewModel.deleteCategory(rawValue: raw, kind: kind), selectedRaw == raw {
                        selectedRaw = fallbackRaw
                    }
                    pendingDeleteRaw = nil
                }
            } message: {
                Text("Связанные операции будут перенесены в безопасную системную категорию.")
            }
            .fullScreenCover(isPresented: $showEditorSheet) {
                CashflowCategoryEditorSheet(
                    mode: editorMode,
                    name: $editorName,
                    icon: $editorIcon
                ) { name, icon in
                    handleSave(name: name, icon: icon)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func openCreateSheet() {
        editorMode = .create
        editorName = ""
        editorIcon = CashflowCustomCategory.defaultIcon
        showEditorSheet = true
    }

    private func openEditSheet(for option: CashflowCategoryOption) {
        editorMode = .edit(rawValue: option.rawValue)
        editorName = option.displayName
        editorIcon = option.icon
        showEditorSheet = true
    }

    private func handleSave(name: String, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch editorMode {
        case .create:
            if let created = viewModel.createCustomCategory(kind: kind, name: trimmed, icon: icon) {
                selectedRaw = created.rawValue
            }

        case .edit(let rawValue):
            guard viewModel.renameCategory(
                rawValue: rawValue,
                kind: kind,
                newName: trimmed,
                newIcon: icon
            ) else { return }

            if let resolved = viewModel.categoryOptions(for: kind).first(where: {
                $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
            }) {
                selectedRaw = resolved.rawValue
            } else if selectedRaw == rawValue {
                selectedRaw = fallbackRaw
            }
        }

        showEditorSheet = false
    }
}

struct CashflowCategoryEditorSheet: View {
    private enum IconPickerTab: String, CaseIterable, Identifiable {
        case emoji = "Эмодзи"
        case symbols = "Иконки"

        var id: String { rawValue }
    }

    let mode: CashflowCategoryEditorMode
    @Binding var name: String
    @Binding var icon: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool
    @State private var selectedTab: IconPickerTab = .emoji
    @State private var iconSearchText: String = ""

    private var title: String {
        switch mode {
        case .create: return "Новая категория"
        case .edit: return "Редактировать категорию"
        }
    }

    private var filteredSymbolIcons: [String] {
        let query = iconSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return CashflowCustomCategory.allowedSFSymbolIcons }
        return CashflowCustomCategory.allowedSFSymbolIcons.filter { $0.lowercased().contains(query) }
    }

    private var visibleIcons: [String] {
        switch selectedTab {
        case .emoji:
            return CashflowCustomCategory.allowedEmojiIcons
        case .symbols:
            return filteredSymbolIcons
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        FinancesSectionHeader(title: "Название")
                        FinancesGlassCard {
                            TextField("Введите название", text: $name)
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(AppColors.textPrimary)
                                .focused($isNameFieldFocused)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }

                        FinancesSectionHeader(title: "Иконка")
                        FinancesGlassCard {
                            VStack(spacing: 12) {
                                Picker("Тип иконки", selection: $selectedTab) {
                                    ForEach(IconPickerTab.allCases) { tab in
                                        Text(tab.rawValue).tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)

                                if selectedTab == .symbols {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(AppColors.textTertiary)
                                        TextField("Поиск иконки (например: car, cart, heart)", text: $iconSearchText)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundStyle(AppColors.textPrimary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.08))
                                    )
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                                    ForEach(visibleIcons, id: \.self) { symbol in
                                    Button {
                                        icon = symbol
                                    } label: {
                                        CashflowCategoryIconView(
                                            icon: symbol,
                                            fontSize: 22,
                                            fontWeight: .semibold,
                                            tint: AnyShapeStyle(icon == symbol ? AppColors.textPrimary : AppColors.textSecondary)
                                        )
                                            .frame(width: 54, height: 54)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(icon == symbol ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                            .stroke(Color.white.opacity(icon == symbol ? 0.24 : 0.10), lineWidth: 1)
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            }
                            .padding(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(AppColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        onSave(name, icon)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    isNameFieldFocused = true
                }
                selectedTab = CashflowCustomCategory.isSFSymbolIcon(icon) ? .symbols : .emoji
                iconSearchText = ""
            }
        }
    }
}
