//
//  CreditEditorView.swift
//  millio
//
//  Created by Александр Сидоркин on 27.01.2026.
//

import SwiftUI

// MARK: - Credit Editor View

struct CreditEditorView: View {
    @ObservedObject var viewModel: CreditViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var remainingAmountText: String = ""
    @State private var monthlyPaymentText: String = ""
    @State private var selectedCurrency: String = SettingsManager.shared.primaryCurrencyCode
    @State private var selectedCreditType: CreditType = .consumer
    @State private var isFavorite: Bool = false
    @State private var paymentMode: CreditPaymentMode = .dayOfMonth
    @State private var paymentDayOfMonth: Int = max(1, min(31, Calendar.current.component(.day, from: Date())))
    @State private var nextPaymentDate: Date = Date()
    @State private var reminderEnabled: Bool = false
    @State private var reminderDaysBeforeText: String = ""
    @State private var reminderTime: Date = Date()
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    @State private var showCryptoProAlert: Bool = false

    init(viewModel: CreditViewModel, onClose: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        mainInfoSection
                        creditParamsSection
                        reminderSection
                        additionalSection
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
            }
            .navigationTitle(
                viewModel.state.editingCredit == nil
                    ? String(localized: "finances.editor.credit.new_title")
                    : String(localized: "finances.editor.credit.edit_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "finances.common.cancel")) {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "finances.common.save")) {
                        saveCredit()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.creditsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }

                if onDelete != nil, viewModel.state.editingCredit != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(String(localized: "finances.common.delete"), role: .destructive) {
                            onDelete?()
                        }
                    }
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingCredit {
                    name = editing.name
                    amountText = AmountInputFormatter.display(AmountInputFormatter.plainString(from: editing.amount))
                    remainingAmountText = AmountInputFormatter.display(
                        AmountInputFormatter.plainString(from: editing.remainingAmount)
                    )
                    monthlyPaymentText = AmountInputFormatter.display(
                        AmountInputFormatter.plainString(from: editing.monthlyPayment)
                    )
                    selectedCurrency = editing.currency
                    selectedCreditType = editing.creditType
                    isFavorite = editing.isFavorite
                    paymentMode = editing.paymentMode
                    paymentDayOfMonth = editing.paymentDayOfMonth ?? paymentDayOfMonth
                    nextPaymentDate = editing.nextPaymentDate ?? Date()
                    reminderEnabled = editing.reminderEnabled
                    reminderDaysBeforeText = editing.reminderDaysBefore.map { String($0) } ?? ""
                    reminderTime = editing.reminderTime ?? defaultReminderTime()
                }

                loadAvailableCurrencies()
            }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
                    let canUseCrypto = EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
                    CurrencyPickerView(
                        allCodes: availableCurrencies,
                        searchText: $currencySearchText,
                        selectedCodes: favoriteCodes,
                        favoriteCodes: Set(favoriteCodes),
                        currentSelection: selectedCurrency,
                        primaryPinnedCode: SettingsManager.shared.primaryCurrencyCode,
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
                    .navigationTitle(String(localized: "finances.add_account.currency_picker.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "finances.common.cancel")) {
                                showCurrencyPicker = false
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .premiumUpsellAlert(
                isPresented: $showCryptoProAlert,
                titleKey: "monetization.crypto.pro_title",
                message: String(localized: "monetization.crypto.pro_message"),
                onSubscribe: { router.push(.subscription) }
            )
        }
    }
    
    private var mainInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.editor.section.main_info"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    TextField(String(localized: "finances.editor.credit.name_placeholder"), text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var creditParamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.editor.credit.params_section"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "finances.add_account.credit.amount"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { amountText },
                            set: { newValue in
                                amountText = AmountInputFormatter.display(newValue)
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
                        Text(String(localized: "finances.add_account.credit.remaining_debt"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { remainingAmountText },
                            set: { newValue in
                                remainingAmountText = AmountInputFormatter.display(newValue)
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
                        Text(String(localized: "finances.add_account.credit.monthly_payment"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { monthlyPaymentText },
                            set: { newValue in
                                monthlyPaymentText = AmountInputFormatter.display(newValue)
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
                        Text(String(localized: "finances.add_account.credit.payment_mode"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker(String(localized: "finances.add_account.credit.payment_mode"), selection: $paymentMode) {
                            ForEach(CreditPaymentMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                    FinancesRowDivider()

                    if paymentMode == .dayOfMonth {
                        HStack {
                            Text(String(localized: "finances.add_account.credit.payment_day"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Menu {
                                ForEach(1...31, id: \.self) { day in
                                    Button("\(day)") {
                                        paymentDayOfMonth = day
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("\(paymentDayOfMonth)")
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    } else {
                        DatePicker(String(localized: "finances.add_account.credit.next_payment_date"), selection: $nextPaymentDate, displayedComponents: .date)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.add_account.credit.reminder.section"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Toggle(String(localized: "finances.add_account.credit.reminder.toggle"), isOn: $reminderEnabled)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                    if reminderEnabled {
                        FinancesRowDivider()

                        HStack {
                            Text(String(localized: "finances.add_account.credit.reminder.days_before"))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { reminderDaysBeforeText },
                                set: { newValue in
                                    reminderDaysBeforeText = String(newValue.filter(\.isNumber))
                                }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: 100)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        FinancesRowDivider()

                        DatePicker(String(localized: "finances.add_account.credit.reminder.time"), selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    
    private var additionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.editor.section.additional"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "finances.add_account.field.currency"))
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
                        Text(String(localized: "finances.editor.credit.type_label"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Picker(String(localized: "finances.editor.credit.type_label"), selection: $selectedCreditType) {
                            ForEach(CreditType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .tint(AppColors.textTertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    Toggle(String(localized: "finances.add_account.favorite"), isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    
                    FinancesRowDivider()

                    HStack {
                        Text(String(localized: "finances.add_account.total_impact.title"))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(String(localized: "finances.add_account.total_impact.decreases"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.error.opacity(0.9))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.isEmpty &&
        parseNumber(amountText) != nil && parseNumber(amountText)! > 0 &&
        parseNumber(remainingAmountText) != nil && parseNumber(remainingAmountText)! >= 0
    }

    // MARK: - Currency Loading

    private func loadAvailableCurrencies() {
        Task {
            let currentSelectedCurrency = await MainActor.run {
                isLoadingCurrencies = true
                return selectedCurrency
            }

            let sortedCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: [currentSelectedCurrency])

            await MainActor.run {
                availableCurrencies = sortedCurrencies
                isLoadingCurrencies = false
            }
        }
    }

    // MARK: - Number Formatting Helpers

    private func normalizeNumber(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
    }

    private func normalizeDecimal(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: ".")
    }

    private func parseNumber(_ text: String) -> Double? {
        AmountInputFormatter.parse(text)
    }

    private func parseDecimal(_ text: String) -> Double? {
        let normalized = normalizeDecimal(text)
        return Double(normalized)
    }

    private func formatNumberForDisplay(_ text: String) -> String {
        AmountInputFormatter.display(text)
    }

    private func saveCredit() {
        guard let amount = parseNumber(amountText),
              let remainingAmount = parseNumber(remainingAmountText) else {
            return
        }
        let endDate = resolvedEndDate()
        let monthlyPayment = parseNumber(monthlyPaymentText) ?? resolvedMonthlyPayment(for: amount)
        let reminderDaysBefore = parseReminderDays(reminderDaysBeforeText)

        viewModel.handle(.updateCredit(
            name: name,
            amount: amount,
            monthlyPayment: monthlyPayment,
            endDate: endDate,
            remainingAmount: remainingAmount,
            currency: selectedCurrency,
            bank: resolvedBank(),
            creditType: selectedCreditType,
            isFavorite: isFavorite,
            paymentMode: paymentMode,
            paymentDayOfMonth: paymentMode == .dayOfMonth ? paymentDayOfMonth : nil,
            nextPaymentDate: paymentMode == .nextDate ? nextPaymentDate : nil,
            reminderEnabled: reminderEnabled,
            reminderDaysBefore: reminderEnabled ? reminderDaysBefore : nil,
            reminderTime: reminderEnabled ? reminderTime : nil,
            includeInTotal: true,
            uniqueID: nil
        ))

        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func resolvedEndDate() -> Date {
        if let editing = viewModel.state.editingCredit, let endDate = editing.endDate {
            return endDate
        }
        return Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    }

    private func resolvedMonthlyPayment(for amount: Double) -> Double {
        if let editing = viewModel.state.editingCredit {
            return editing.monthlyPayment
        }
        return amount / 12.0
    }

    private func parseReminderDays(_ value: String) -> Int? {
        guard !value.isEmpty, let parsed = Int(value) else { return nil }
        return max(0, parsed)
    }

    private func defaultReminderTime() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func resolvedBank() -> Bank {
        viewModel.state.editingCredit?.bank ?? .other
    }
}
