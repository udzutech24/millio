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
    static let amountMaxFractionDigits = 2
    static let amountBaseFontSize: CGFloat = 38
    static let amountCompactFontSize: CGFloat = 32
    static let amountMinimumScaleFactor: CGFloat = 0.72
    static let amountRowHeight: CGFloat = 96

    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

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
    @State private var selectedInvestmentID: String? = nil
    @State private var selectedToCardID: String? = nil
    @State private var selectedIncomeCategoryRaw: String? = nil
    @State private var selectedExpenseCategoryRaw: String? = nil
    @State private var note: String = ""
    @State private var recurrenceRule: CashflowRecurrenceRule = .none
    @State private var recurrenceWeekdays: Set<CashflowRecurrenceWeekday> = []
    @State private var shouldAffectCardBalance: Bool = true
    @State private var availableCurrencies: [String] = []
    @State private var isLoadingCurrencies: Bool = false
    @State private var isAmountOverBalance: Bool = false
    @State private var isSavingTransaction: Bool = false
    @State private var showSaveErrorAlert: Bool = false
    @State private var validationTask: Task<Void, Never>? = nil
    
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    @State private var showCategorySheet: Bool = false
    @State private var showRecurrenceRulePicker: Bool = false
    @State private var showCryptoProAlert: Bool = false
    @State private var showAffectBalanceHelpAlert: Bool = false
    @FocusState private var isAmountFieldFocused: Bool

    private let primarySecondaryText = Color.white.opacity(0.78)
    private let innerGlassFill = Color.white.opacity(0.022)
    private let currentRoute: AppRoute = .cashflow

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
        initialTransactionDate: Date? = nil,
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
            _selectedInvestmentID = State(initialValue: transaction.investmentID)
            _selectedToCardID = State(initialValue: transaction.toCardID)
            _selectedIncomeCategoryRaw = State(initialValue: transaction.incomeCategoryRaw)
            _selectedExpenseCategoryRaw = State(initialValue: transaction.expenseCategoryRaw)
            _note = State(initialValue: transaction.note ?? "")
            _recurrenceRule = State(initialValue: transaction.recurrenceRule)
            _recurrenceWeekdays = State(initialValue: transaction.recurrenceWeekdays)
            _shouldAffectCardBalance = State(initialValue: transaction.affectsCardBalance)
        } else if let type = transactionType {
            _selectedTransactionType = State(initialValue: type)
            _transactionDate = State(initialValue: initialTransactionDate ?? Date())
            if type == .income {
                _selectedIncomeCategoryRaw = State(initialValue: preselectedIncomeCategoryRaw ?? IncomeCategory.salary.rawValue)
            } else if type == .expense {
                _selectedExpenseCategoryRaw = State(initialValue: preselectedExpenseCategoryRaw ?? ExpenseCategory.groceries.rawValue)
            }
            _recurrenceRule = State(initialValue: initialRecurrenceRule ?? .none)
            _recurrenceWeekdays = State(initialValue: [])
            _shouldAffectCardBalance = State(initialValue: true)
        } else {
            _selectedTransactionType = State(initialValue: .expense)
            _transactionDate = State(initialValue: initialTransactionDate ?? Date())
            _recurrenceRule = State(initialValue: initialRecurrenceRule ?? .none)
            _recurrenceWeekdays = State(initialValue: [])
            _shouldAffectCardBalance = State(initialValue: true)
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
                        .foregroundStyle((isValid && !isSavingTransaction) ? Color(hex: "6DFFC7") : AppColors.textSecondary.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .disabled(!isValid || isSavingTransaction)
                .buttonStyle(.plain)
            }
        }
        .alert(
            String(
                localized: "cashflow.editor.save_failed.title",
                defaultValue: "Could not save transaction",
                comment: "Title for failed cashflow transaction save alert"
            ),
            isPresented: $showSaveErrorAlert
        ) {
            Button(
                String(
                    localized: "cashflow.common.ok",
                    defaultValue: "OK",
                    comment: "Confirmation button title"
                ),
                role: .cancel
            ) {}
        } message: {
            Text(
                String(
                    localized: "cashflow.editor.save_failed.message",
                    defaultValue: "The transaction was not saved. Check the selected account, date, and available balance, then try again.",
                    comment: "Message for failed cashflow transaction save alert"
                )
            )
        }
        .alert(
            autoApplyToggleTitle,
            isPresented: $showAffectBalanceHelpAlert
        ) {
            Button(
                String(
                    localized: "cashflow.common.ok",
                    defaultValue: "OK",
                    comment: "Confirmation button title"
                ),
                role: .cancel
            ) {}
        } message: {
            Text(autoApplyToggleHelpMessage)
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
                amountDisplayText = Self.formattedAmountDisplayText(from: amountText)
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
            let sanitized = Self.sanitizedAmountText(from: newValue)
            let formatted = Self.formattedAmountDisplayText(from: sanitized)
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
            if selectedTransactionType != .income && selectedTransactionType != .expense {
                shouldAffectCardBalance = true
            }
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
                let canUseCrypto = EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
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
                    badgeForCode: { code in
                        guard CurrencySelectionSupport.isCrypto(code), !canUseCrypto else { return nil }
                        return .pro
                    },
                    onSelect: { currency in
                        if CurrencySelectionSupport.isCrypto(currency), !canUseCrypto {
                            showCryptoProAlert = true
                            return
                        }
                        selectedCurrency = currency
                        showCurrencyPicker = false
                    }
                )
                .navigationTitle("cashflow.editor.transaction_currency")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showCurrencyPicker = false
                        }
                        .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .premiumUpsellAlert(
                    isPresented: $showCryptoProAlert,
                    titleKey: "monetization.crypto.pro_title",
                    message: String(localized: "monetization.crypto.pro_message"),
                    onSubscribe: { router.push(.subscription) }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRecurrenceRulePicker) {
            CashflowRecurrenceRulePickerSheet(
                selection: $recurrenceRule,
                selectedWeekdays: $recurrenceWeekdays,
                defaultWeekday: defaultWeeklyRecurrenceWeekday
            )
        }
    }

    private var resolvedNavigationTitle: String {
        if let customNavigationTitle {
            return customNavigationTitle
        }
        return editingTransaction == nil ? "New transaction" : "Edit"
    }

    // MARK: - Тип операции

    private var transactionTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "cashflow.editor.section.transaction_type"))
            editorCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("cashflow.editor.transaction_type")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker(String(localized: "cashflow.editor.transaction_type"), selection: $selectedTransactionType) {
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
                    recurrenceWeekdays = []
                }
            }
        }
    }

    // MARK: - Категория

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "cashflow.editor.section.category"))
            editorCard {
                Button {
                    fireLightImpact()
                    showCategorySheet = true
                } label: {
                    HStack {
                        Text(selectedTransactionType == .income ? "cashflow.editor.income_category" : "cashflow.editor.expense_category")
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
            sectionTitle(String(localized: "cashflow.editor.section.main_info"))
            editorCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("cashflow.editor.amount")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { amountDisplayText },
                            set: { amountDisplayText = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(
                            size: Self.amountFontSize(for: amountDisplayText),
                            weight: .bold,
                            design: .rounded
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(Self.amountMinimumScaleFactor)
                        .foregroundStyle(AppColors.textPrimary)
                        .focused($isAmountFieldFocused)
                        .frame(minWidth: 170, maxWidth: .infinity, alignment: .trailing)
                        .layoutPriority(1)
                    }
                    .frame(minHeight: Self.amountRowHeight)
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
                        if showsAffectCardBalanceToggle {
                            FinancesRowDivider()
                            affectCardBalanceToggleRow
                        }
                        FinancesRowDivider()
                    } else {
                        FinancesRowDivider()
                        standaloneCurrencyRow
                        FinancesRowDivider()
                    }

                    HStack {
                        Text("cashflow.editor.date")
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

    private var standaloneCurrencyRow: some View {
        HStack {
            Text("cashflow.editor.currency")
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
    }

    private var selectedCategorySummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                String(
                    localized: selectedTransactionType == .income
                        ? "cashflow.editor.section.selected_income"
                        : "cashflow.editor.section.selected_expense"
                )
            )
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
            sectionTitle(String(localized: "cashflow.editor.section.recurrence"))
            editorCard {
                Button {
                    showRecurrenceRulePicker = true
                } label: {
                    HStack(spacing: 10) {
                        Text("cashflow.editor.frequency")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(recurrenceRule.displayName)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        VStack(spacing: 10) {
            compactCurrencyAndAccountRow

            if selectableAccountsForCurrentSelection.isEmpty {
                VStack(spacing: 10) {
                    Text("cashflow.editor.no_cards_in_currency")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Button {
                        openFinancesAddCard()
                    } label: {
                        Text("cashflow.editor.add_card_in_finances")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if shouldValidateBalance, let availableText = availableBalanceText {
                Text(availableText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isAmountOverBalance {
                Text("cashflow.editor.insufficient_funds")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private var compactCurrencyAndAccountRow: some View {
        HStack(spacing: 10) {
            compactSelectorButton(
                title: String(localized: "cashflow.editor.currency"),
                value: selectedCurrency,
                isLoading: isLoadingCurrencies
            ) {
                showCurrencyPicker = true
            }

            compactAccountSelector
        }
    }

    private var compactAccountSelector: some View {
        Menu {
            ForEach(selectableAccountsForCurrentSelection) { account in
                Button(account.pickerTitle) {
                    updateSelectedAccount(using: account.id)
                }
            }
        } label: {
            compactSelectorLabel(
                title: compactAccountLabel,
                value: selectedAccountTitle,
                usesPlaceholderStyle: selectableAccountsForCurrentSelection.isEmpty || selectedAccountPickerID.isEmpty
            )
        }
        .disabled(selectableAccountsForCurrentSelection.isEmpty)
        .opacity(selectableAccountsForCurrentSelection.isEmpty ? 0.55 : 1)
        .frame(maxWidth: .infinity)
    }

    private func compactSelectorButton(
        title: String,
        value: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isLoading {
                compactSelectorLabel(
                    title: title,
                    customValue: {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(AppColors.textTertiary)
                    }
                )
            } else {
                compactSelectorLabel(title: title, value: value)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func compactSelectorLabel<CustomValue: View>(
        title: String,
        value: String? = nil,
        usesPlaceholderStyle: Bool = false,
        @ViewBuilder customValue: () -> CustomValue = { EmptyView() }
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(.uppercase)
                    .lineLimit(1)

                if let value {
                    Text(value)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(usesPlaceholderStyle ? AppColors.textSecondary : AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    customValue()
                }
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary.opacity(0.9))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var compactAccountLabel: String {
        selectedTransactionType == .income
            ? String(localized: "cashflow.editor.account")
            : String(localized: "cashflow.editor.card")
    }

    private var selectedAccountTitle: String {
        if let selected = selectableAccountsForCurrentSelection.first(where: { $0.id == selectedAccountPickerID }) {
            return selected.pickerTitle
        }
        return selectedTransactionType == .income
            ? String(localized: "cashflow.editor.select_account")
            : String(localized: "cashflow.editor.select_card")
    }

    @ViewBuilder
    private var transferCardContent: some View {
        if transferCardOptions.isEmpty {
            Text("cashflow.editor.no_available_cards")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
        } else {
            HStack {
                Text("cashflow.editor.from_card")
                    .foregroundStyle(AppColors.textPrimary)
                    .layoutPriority(1)
                Spacer()
                Picker(String(localized: "cashflow.editor.from_card"), selection: Binding(
                    get: { selectedCardID ?? "" },
                    set: { selectedCardID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("cashflow.editor.select_card").tag("")
                    ForEach(transferCardOptions.filter { $0.cardID != selectedToCardID }) { account in
                        Text(account.pickerTitle).tag(account.cardID ?? "")
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
                Text("cashflow.editor.insufficient_funds")
                    .font(.caption)
                    .foregroundStyle(AppColors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
            }

            FinancesRowDivider()

            HStack {
                Text("cashflow.editor.to_card")
                    .foregroundStyle(AppColors.textPrimary)
                    .layoutPriority(1)
                Spacer()
                Picker(String(localized: "cashflow.editor.to_card"), selection: Binding(
                    get: { selectedToCardID ?? "" },
                    set: { selectedToCardID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("cashflow.editor.select_card").tag("")
                    ForEach(transferCardOptions.filter { $0.cardID != selectedCardID }) { account in
                        Text(account.pickerTitle).tag(account.cardID ?? "")
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

    private var affectCardBalanceToggleRow: some View {
        Toggle(
            isOn: $shouldAffectCardBalance,
            label: {
                HStack(alignment: .center, spacing: 6) {
                    Text(autoApplyToggleTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Button {
                        showAffectBalanceHelpAlert = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        )
        .toggleStyle(.switch)
        .tint(getGradientColors().first ?? Color.white)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    private var autoApplyToggleTitle: String {
        String(localized: "cashflow.bulk_expense.affect_balance")
    }

    private var autoApplyToggleHelpMessage: String {
        switch selectedTransactionType {
        case .income:
            return String(localized: "cashflow.editor.affect_balance.subtitle.income")
        case .expense:
            return String(localized: "cashflow.editor.affect_balance.subtitle.expense")
        default:
            return String(localized: "cashflow.editor.affect_balance.subtitle.expense")
        }
    }

    // MARK: - Дополнительно

    private var additionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "Additional"))
            editorCard {
                VStack(spacing: 0) {
                    TextField("cashflow.editor.comment", text: $note, axis: .vertical)
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

    private var showsAffectCardBalanceToggle: Bool {
        selectedTransactionType == .income || selectedTransactionType == .expense
    }

    private var shouldShowCardSelectionInMainInfo: Bool {
        Self.mainInfoRows(for: selectedTransactionType).contains(.fromCard)
    }

    private var selectableAccountsForCurrentSelection: [CashflowSelectableAccount] {
        Self.selectableAccounts(
            cards: viewModel.state.availableCards,
            investments: viewModel.state.availableInvestments,
            financeAccounts: viewModel.state.availableFinanceAccounts,
            transactionType: selectedTransactionType,
            currency: selectedCurrency
        )
    }

    private var selectedAccountPickerID: String {
        if let selectedCardID {
            return "card:\(selectedCardID)"
        }
        if let selectedInvestmentID {
            return "investment:\(selectedInvestmentID)"
        }
        return ""
    }

    private var transferCardOptions: [CashflowSelectableAccount] {
        Self.selectableAccounts(
            cards: viewModel.state.availableCards,
            investments: [],
            financeAccounts: viewModel.state.availableFinanceAccounts,
            transactionType: .transfer,
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
              let amount = AmountInputFormatter.parse(amountText),
              amount > 0 else {
            return false
        }

        switch selectedTransactionType {
        case .income, .expense:
            return (selectedCardID != nil || selectedInvestmentID != nil) && !isAmountOverBalance
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

    private func openFinancesAddCard() {
        appState.pendingOpenFinanceAddCard = true
        dismiss()
        DispatchQueue.main.async {
            MiniAppNavigation.navigate(to: .finances, from: currentRoute, router: router)
        }
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
        guard let amount = AmountInputFormatter.parse(amountText),
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
        let effectiveRecurrenceWeekdays: Set<CashflowRecurrenceWeekday> = {
            guard effectiveRecurrenceRule == .weekly else { return [] }
            return recurrenceWeekdays.isEmpty ? [defaultWeeklyRecurrenceWeekday] : recurrenceWeekdays
        }()
        let resolvedRecurrenceSeriesID: String? = {
            if effectiveRecurrenceRule == .none {
                if editingTransaction?.isRecurringTemplate == true {
                    return nil
                }
                return editingTransaction?.recurrenceSeriesID
            }
            return editingTransaction?.recurrenceSeriesID ?? UUID().uuidString
        }()

        let transaction = CashflowTransaction(
            transactionType: selectedTransactionType,
            amount: amount,
            currency: selectedCurrency,
            transactionDate: transactionDate,
            cardID: selectedCardID,
            toCardID: selectedToCardID,
            investmentID: selectedInvestmentID,
            incomeCategoryRaw: resolvedIncomeCategoryRaw,
            expenseCategoryRaw: resolvedExpenseCategoryRaw,
            note: note.isEmpty ? nil : note,
            recurrenceRule: effectiveRecurrenceRule,
            recurrenceWeekdays: effectiveRecurrenceWeekdays,
            recurrenceSeriesID: resolvedRecurrenceSeriesID,
            affectsCardBalance: showsAffectCardBalanceToggle ? shouldAffectCardBalance : true
        )

        transaction.transactionTypeRaw = selectedTransactionType.rawValue
        transaction.amount = amount
        transaction.currency = selectedCurrency
        transaction.transactionDate = transactionDate
        transaction.cardID = selectedCardID
        transaction.investmentID = selectedInvestmentID
        transaction.toCardID = selectedToCardID
        transaction.incomeCategoryRaw = resolvedIncomeCategoryRaw
        transaction.expenseCategoryRaw = resolvedExpenseCategoryRaw
        transaction.note = note.isEmpty ? nil : note
        transaction.recurrenceRuleRaw = effectiveRecurrenceRule.rawValue
        transaction.recurrenceWeekdays = effectiveRecurrenceWeekdays
        transaction.recurrenceSeriesID = resolvedRecurrenceSeriesID
        transaction.affectsCardBalance = showsAffectCardBalanceToggle ? shouldAffectCardBalance : true

        isSavingTransaction = true
        Task {
            let didSave = await viewModel.persistTransaction(
                transaction,
                replacing: editingTransaction
            )
            await MainActor.run {
                isSavingTransaction = false
                guard didSave else {
                    showSaveErrorAlert = true
                    return
                }

                fireSuccessHaptic()
                if let onSave {
                    onSave()
                } else {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Currency Loading

    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }

            availableCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: [selectedCurrency])
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
        selectedTransactionType == .transfer || (selectedTransactionType == .expense && shouldAffectCardBalance)
    }

    private var availableBalanceText: String? {
        guard shouldValidateBalance,
              let cardID = selectedCardID,
              let card = viewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID }) else {
            return nil
        }

        let formatted = formatNumberForDisplay(card.balance)
        return String(
            format: String(localized: "cashflow.editor.available_format"),
            formatted,
            card.currency
        )
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
                    on: date,
                    replacing: editingTransaction
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

    private func updateSelectedAccount(using selectionID: String) {
        if selectionID.isEmpty {
            selectedCardID = nil
            selectedInvestmentID = nil
            return
        }

        guard let selection = selectableAccountsForCurrentSelection.first(where: { $0.id == selectionID }) else {
            selectedCardID = nil
            selectedInvestmentID = nil
            return
        }

        selectedCardID = selection.cardID
        selectedInvestmentID = selection.investmentID
    }

    private func synchronizeSelectedCards() {
        let selectableAccounts = selectableAccountsForCurrentSelection
        let selectableCardIDs = Set(selectableAccounts.compactMap(\.cardID))
        let selectableInvestmentIDs = Set(selectableAccounts.compactMap(\.investmentID))

        if let selectedCardID, !selectableCardIDs.contains(selectedCardID) {
            self.selectedCardID = nil
        }

        if let selectedInvestmentID, !selectableInvestmentIDs.contains(selectedInvestmentID) {
            self.selectedInvestmentID = nil
        }

        if selectedTransactionType == .transfer {
            if selectedCardID == nil {
                selectedCardID = transferCardOptions.first?.cardID
            }
            if selectedToCardID == selectedCardID {
                selectedToCardID = nil
            }
            selectedInvestmentID = nil
            return
        }

        if selectedCardID == nil && selectedInvestmentID == nil {
            selectedCardID = selectableAccounts.first?.cardID
            selectedInvestmentID = selectableAccounts.first?.investmentID
        }
        selectedToCardID = nil
    }

    private var defaultWeeklyRecurrenceWeekday: CashflowRecurrenceWeekday {
        let weekday = Calendar.current.component(.weekday, from: transactionDate)
        return CashflowRecurrenceWeekday(rawValue: weekday) ?? .monday
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
    static func sanitizedAmountText(from value: String) -> String {
        AmountInputFormatter.sanitize(value, maxFractionDigits: amountMaxFractionDigits)
    }

    static func formattedAmountDisplayText(from value: String) -> String {
        AmountInputFormatter.display(value, maxFractionDigits: amountMaxFractionDigits)
    }

    static func amountFontSize(for value: String) -> CGFloat {
        let significantCharacters = value.filter { $0.isWholeNumber }.count
        return significantCharacters >= 7 ? amountCompactFontSize : amountBaseFontSize
    }

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
            return [.amount, .currency, .fromCard, .date]
        case .transfer:
            return [.amount, .currency, .fromCard, .toCard, .date]
        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return [.amount, .currency, .date]
        }
    }

    static func selectableAccounts(
        cards: [Card],
        investments: [Investment],
        financeAccounts: [FinanceAccount] = [],
        transactionType: CashflowTransactionType,
        currency: String
    ) -> [CashflowSelectableAccount] {
        CashflowSelectableAccountResolver.options(
            cards: cards,
            investments: investments,
            financeAccounts: financeAccounts,
            transactionType: transactionType,
            currency: currency
        )
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
        kind == .income
            ? String(localized: "cashflow.editor.category_sheet.title.income")
            : String(localized: "cashflow.editor.category_sheet.title.expense")
    }

    private var createButtonTitle: String {
        kind == .income
            ? String(localized: "cashflow.editor.category_sheet.create.income")
            : String(localized: "cashflow.editor.category_sheet.create.expense")
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
                            TextField("cashflow.editor.search_category", text: $searchText)
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
                                        Button(String(localized: "cashflow.common.edit")) {
                                            openEditSheet(for: option)
                                        }
                                        if viewModel.canDeleteCategory(rawValue: option.rawValue, kind: kind) {
                                            Button(String(localized: "cashflow.history.detail.delete"), role: .destructive) {
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
                    Button(String(localized: "cashflow.common.close")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
            .alert(String(localized: "cashflow.editor.delete_category.title"), isPresented: $showDeleteAlert) {
                Button(String(localized: "cashflow.common.cancel"), role: .cancel) {
                    pendingDeleteRaw = nil
                }
                Button(String(localized: "cashflow.history.detail.delete"), role: .destructive) {
                    guard let raw = pendingDeleteRaw else { return }
                    if viewModel.deleteCategory(rawValue: raw, kind: kind), selectedRaw == raw {
                        selectedRaw = fallbackRaw
                    }
                    pendingDeleteRaw = nil
                }
            } message: {
                Text("cashflow.editor.delete_category.message")
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

private struct CashflowRecurrenceRulePickerSheet: View {
    @Binding var selection: CashflowRecurrenceRule
    @Binding var selectedWeekdays: Set<CashflowRecurrenceWeekday>
    let defaultWeekday: CashflowRecurrenceWeekday
    @Environment(\.dismiss) private var dismiss

    private let recurringRules: [CashflowRecurrenceRule] = [
        .weekly,
        .monthly,
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    recurrenceRow(for: .none)
                }

                Section {
                    ForEach(recurringRules, id: \.self) { rule in
                        recurrenceRow(for: rule)
                    }
                }

                if selection == .weekly {
                    Section {
                        weekdaySelectorRow
                    } header: {
                        Text(weeklyDaysTitle)
                    } footer: {
                        Text(weeklyDaysHint)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(GradientBackground())
            .navigationTitle(String(localized: "cashflow.editor.section.recurrence"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(okButtonTitle) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func recurrenceRow(for rule: CashflowRecurrenceRule) -> some View {
        Button {
            selection = rule
            if rule == .weekly, selectedWeekdays.isEmpty {
                selectedWeekdays = [defaultWeekday]
            }
            if rule != .weekly {
                dismiss()
            }
        } label: {
            HStack {
                Text(rule.displayName)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                if rule == .weekly {
                    Text(weeklySelectionSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
                if selection == rule {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var weekdaySelectorRow: some View {
        let ordered = CashflowRecurrenceWeekday.orderedForCurrentLocale()
        return HStack(spacing: 8) {
            ForEach(ordered, id: \.rawValue) { weekday in
                let isSelected = selectedWeekdays.contains(weekday)
                Button {
                    toggleWeekday(weekday)
                } label: {
                    Text(weekday.shortDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.95) : AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? (AppColors.cashflowGradient.first ?? Color.blue).opacity(0.75) : Color.white.opacity(0.06))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(isSelected ? 0.55 : 0.16), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggleWeekday(_ weekday: CashflowRecurrenceWeekday) {
        if selectedWeekdays.contains(weekday) {
            if selectedWeekdays.count > 1 {
                selectedWeekdays.remove(weekday)
            }
            return
        }
        selectedWeekdays.insert(weekday)
    }

    private var weeklySelectionSummary: String {
        let ordered = CashflowRecurrenceWeekday.orderedForCurrentLocale()
        let selected = ordered.filter { selectedWeekdays.contains($0) }
        guard !selected.isEmpty else {
            return String(
                localized: "cashflow.recurrence.weekly.none_selected",
                defaultValue: "Select days",
                comment: "Weekly recurrence placeholder when no weekdays selected"
            )
        }
        return selected.map(\.shortDisplayName).joined(separator: ", ")
    }

    private var isRussianLocale: Bool {
        Locale.autoupdatingCurrent.identifier.lowercased().hasPrefix("ru")
    }

    private var okButtonTitle: String {
        isRussianLocale ? "Ок" : "OK"
    }

    private var weeklyDaysTitle: String {
        isRussianLocale ? "Дни недели" : "Days of week"
    }

    private var weeklyDaysHint: String {
        isRussianLocale ? "Можно выбрать несколько дней" : "You can choose several days"
    }
}

struct CashflowCategoryEditorSheet: View {
    private enum IconPickerTab: String, CaseIterable, Identifiable {
        case emoji = "Emoji"
        case symbols = "Icons"

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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var title: String {
        switch mode {
        case .create: return String(localized: "cashflow.editor.new_category")
        case .edit: return String(localized: "cashflow.editor.edit_category")
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
                        FinancesSectionHeader(title: String(localized: "cashflow.editor.category_name"))
                        FinancesGlassCard {
                            TextField("cashflow.editor.enter_name", text: $name)
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(AppColors.textPrimary)
                                .focused($isNameFieldFocused)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }

                        FinancesSectionHeader(title: String(localized: "cashflow.editor.category_icon"))
                        FinancesGlassCard {
                            VStack(spacing: 12) {
                                Picker(String(localized: "cashflow.editor.icon_type"), selection: $selectedTab) {
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
                                        TextField("cashflow.editor.icon_search_hint", text: $iconSearchText)
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    }
                    .accessibilityLabel(String(localized: "cashflow.common.cancel"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(name, icon)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(canSave ? Color(hex: "6DFFC7") : AppColors.textSecondary.opacity(0.55))
                    }
                    .accessibilityLabel(String(localized: "cashflow.common.save"))
                    .disabled(!canSave)
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
