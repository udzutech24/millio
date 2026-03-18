//
//  FinanceQuickEditAccountView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

enum FinanceQuickEditLayoutPolicy {
    static func showsDeleteButton(for accountType: FinanceAccountType) -> Bool {
        accountType == .card || accountType == .investment
    }
}

struct FinanceQuickEditAccountView: View {
    let account: FinanceAccount
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var amountText: String = ""
    @State private var creditLimitText: String = ""
    @State private var creditDebtText: String = ""
    @State private var isLoading = false
    @State private var showDeleteConfirmation = false
    @FocusState private var isAmountFieldFocused: Bool
    
    var accountInfo: (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool)? {
        viewModel.getAccountInfo(account: account)
    }

    private var marketInvestment: Investment? {
        guard account.accountType == .investment else { return nil }
        return viewModel.state.availableInvestments.first(where: { $0.investmentUniqueID == account.accountID && $0.isMarketPriced })
    }

    private var isMarketInvestment: Bool {
        marketInvestment != nil
    }

    private var currentCreditCard: Card? {
        guard account.accountType == .card else { return nil }
        return viewModel.state.availableCards.first(where: { $0.cardUniqueID == account.accountID && $0.cardType == .credit })
    }

    private var isCreditCard: Bool {
        currentCreditCard != nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                VStack(spacing: 24) {
                    if let info = accountInfo {
                        // Иконка и название счета
                        VStack(spacing: 12) {
                            Image(systemName: info.icon)
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text(info.name)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .padding(.top, 40)
                        
                        Group {
                            if isCreditCard {
                                creditCardQuickForm(currency: info.currency)
                            } else {
                                // Поле ввода суммы
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(fieldTitle)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary)

                                    HStack(spacing: 8) {
                                        TextField("", text: $amountText)
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.leading)
                                            .focused($isAmountFieldFocused)
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)
                                            .onChange(of: amountText) { _, newValue in
                                                syncFormattedText(
                                                    newValue,
                                                    text: $amountText,
                                                    maxFractionDigits: maxFractionDigitsForInput
                                                )
                                            }

                                        Text(valueSuffix(for: info))
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                    .task {
                                        if amountText.isEmpty {
                                            amountText = plainAmountForInput(currentEditableValue(fallbackAmount: info.amount))
                                        }
                                        isAmountFieldFocused = true
                                    }
                                    .padding(20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.black.opacity(0.3))
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                        
                        // Кнопка сохранения
                        Button {
                            save()
                        } label: {
                            Text(String(localized: "finances.common.save"))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: AppColors.incomeGradient,
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    ),
                                                    lineWidth: 2
                                                )
                                        }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || !isValidInput)
                        .opacity(isLoading || !isValidInput ? 0.6 : 1.0)
                        .padding(.horizontal, 24)

                        if FinanceQuickEditLayoutPolicy.showsDeleteButton(for: account.accountType) {
                            deleteAccountButton
                                .padding(.horizontal, 24)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "finances.common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
            .alert(
                deleteConfirmationTitle,
                isPresented: $showDeleteConfirmation
            ) {
                Button(String(localized: "finances.common.cancel"), role: .cancel) {}
                Button(String(localized: "finances.common.delete"), role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text(String(localized: "finances.dynamics.delete_account.confirm.message"))
            }
        }
        .onAppear {
            setupInitialValues()
        }
    }

    private var deleteAccountButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Text(String(localized: "finances.dynamics.delete_account"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.error.opacity(0.92))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppColors.error.opacity(0.22), lineWidth: 0.9)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("finances.quick_edit.delete_account.button")
    }

    @ViewBuilder
    private func creditCardQuickForm(currency: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            quickRow(
                title: String(localized: "finances.add_account.card.credit_limit"),
                text: Binding(
                    get: { creditLimitText },
                    set: { creditLimitText = $0 }
                ),
                suffix: currency
            )

            quickRow(
                title: String(localized: "finances.add_account.card.total_debt"),
                text: Binding(
                    get: { creditDebtText },
                    set: { creditDebtText = $0 }
                ),
                suffix: currency
            )

            HStack {
                Text(String(localized: "finances.add_account.card.remaining_limit"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text("\(formatAmount(creditRemainingLimit)) \(currency)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.25))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.3))
        )
    }

    private func quickRow(title: String, text: Binding<String>, suffix: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: 140)
                .onChange(of: text.wrappedValue) { _, newValue in
                    syncFormattedText(newValue, text: text)
                }
            Text(suffix)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.25))
        )
    }

    private var isValidInput: Bool {
        if isCreditCard {
            guard let limit = parseAmount(creditLimitText),
                  let debt = parseAmount(creditDebtText) else {
                return false
            }
            return limit >= 0 && debt >= 0 && debt <= limit
        }
        guard let amount = parseAmount(amountText) else {
            return false
        }
        return amount >= 0
    }

    private var navigationTitle: String {
        if isCreditCard {
            return String(localized: "finances.quick_edit.title.card")
        }
        return isMarketInvestment
            ? String(localized: "finances.quick_edit.title.quantity")
            : String(localized: "finances.quick_edit.title.amount")
    }

    private var creditRemainingLimit: Double {
        let limit = parseAmount(creditLimitText) ?? 0
        let debt = parseAmount(creditDebtText) ?? 0
        return max(0, limit - debt)
    }

    private var maxFractionDigitsForInput: Int {
        isMarketInvestment ? AmountInputFormatter.marketQuantityFractionDigits : 2
    }

    private func plainAmountForInput(_ amount: Double) -> String {
        AmountInputFormatter.plainString(from: amount, maxFractionDigits: maxFractionDigitsForInput)
    }

    private func parseAmount(_ text: String) -> Double? {
        AmountInputFormatter.parse(
            text,
            maxFractionDigits: isMarketInvestment ? AmountInputFormatter.marketQuantityFractionDigits : 2
        )
    }

    private func syncFormattedText(_ newValue: String, text: Binding<String>, maxFractionDigits: Int = 2) {
        let sanitized = AmountInputFormatter.sanitize(newValue, maxFractionDigits: maxFractionDigits)
        let formatted = AmountInputFormatter.display(sanitized, maxFractionDigits: maxFractionDigits)

        if text.wrappedValue != formatted {
            text.wrappedValue = formatted
        }
    }
    
    private func save() {
        if isCreditCard {
            guard let limit = parseAmount(creditLimitText),
                  let debt = parseAmount(creditDebtText),
                  limit >= 0, debt >= 0, debt <= limit else {
                return
            }
            isLoading = true
            viewModel.handle(.updateCreditCardQuickFields(account: account, creditLimit: limit, debt: debt))
            isLoading = false
            dismiss()
            return
        }
        guard let amount = parseAmount(amountText), amount >= 0 else {
            return
        }
        isLoading = true
        viewModel.handle(.updateAccountAmount(account, amount))
        isLoading = false
        dismiss()
    }

    private func deleteAccount() {
        viewModel.handle(.deleteAccountPermanently(account))
        dismiss()
    }

    private func setupInitialValues() {
        guard let info = accountInfo else { return }
        if isCreditCard, let card = currentCreditCard {
            if creditLimitText.isEmpty {
                creditLimitText = AmountInputFormatter.display(
                    plainAmountForInput(card.creditLimit ?? 0)
                )
            }
            if creditDebtText.isEmpty {
                let debt = max(0, (card.creditLimit ?? 0) - card.balance)
                creditDebtText = AmountInputFormatter.display(plainAmountForInput(debt))
            }
            return
        }
        if amountText.isEmpty {
            amountText = AmountInputFormatter.display(
                plainAmountForInput(currentEditableValue(fallbackAmount: info.amount)),
                maxFractionDigits: maxFractionDigitsForInput
            )
        }
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private var fieldTitle: String {
        if isMarketInvestment {
            return marketInvestment?.category == .crypto
                ? String(localized: "finances.market.field_quantity_coins")
                : String(localized: "finances.market.field_quantity")
        }
        return isCreditCard
            ? String(localized: "finances.quick_edit.field.debt")
            : String(localized: "finances.add_account.field.amount")
    }

    private func valueSuffix(for info: (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool)) -> String {
        if isMarketInvestment {
            return marketInvestment?.category == .crypto
                ? String(localized: "finances.quick_edit.unit.coins_short")
                : String(localized: "finances.investment.unit.shares_short")
        }
        return info.currency
    }

    private func currentEditableValue(fallbackAmount: Double) -> Double {
        if let investment = marketInvestment {
            return investment.marketQuantity ?? 0
        }
        return fallbackAmount
    }

    private var deleteConfirmationTitle: String {
        let name = accountInfo?.name ?? String(localized: "finances.dynamics.chart.account_fallback")
        return FinancesL10n.format("finances.dynamics.delete_account.confirm.title", name)
    }
}
