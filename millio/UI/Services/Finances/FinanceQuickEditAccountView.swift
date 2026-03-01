//
//  FinanceQuickEditAccountView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

struct FinanceQuickEditAccountView: View {
    let account: FinanceAccount
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var amountText: String = ""
    @State private var creditLimitText: String = ""
    @State private var creditDebtText: String = ""
    @State private var isLoading = false
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
                                        TextField("", text: Binding(
                                            get: {
                                                AmountInputFormatter.display(
                                                    amountText,
                                                    maxFractionDigits: maxFractionDigitsForInput
                                                )
                                            },
                                            set: { newValue in
                                                amountText = AmountInputFormatter.sanitize(
                                                    newValue,
                                                    maxFractionDigits: maxFractionDigitsForInput
                                                )
                                            }
                                        ))
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.leading)
                                            .focused($isAmountFieldFocused)
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)

                                        Text(valueSuffix(for: info))
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                    .task {
                                        if amountText.isEmpty {
                                            amountText = plainAmountForInput(currentEditableValue(fallbackAmount: info.amount))
                                        }
                                        try? await Task.sleep(nanoseconds: 100_000_000)
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
                            Text("OK")
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
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .onAppear {
            setupInitialValues()
        }
    }

    @ViewBuilder
    private func creditCardQuickForm(currency: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            quickRow(
                title: "Кредитный лимит",
                text: Binding(
                    get: { AmountInputFormatter.display(creditLimitText) },
                    set: { creditLimitText = AmountInputFormatter.sanitize($0) }
                ),
                suffix: currency
            )

            quickRow(
                title: "Общий долг",
                text: Binding(
                    get: { AmountInputFormatter.display(creditDebtText) },
                    set: { creditDebtText = AmountInputFormatter.sanitize($0) }
                ),
                suffix: currency
            )

            HStack {
                Text("Остаток лимита")
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
            return "Редактирование карты"
        }
        return isMarketInvestment ? "Редактирование количества" : "Редактирование суммы"
    }

    private var creditRemainingLimit: Double {
        let limit = parseAmount(creditLimitText) ?? 0
        let debt = parseAmount(creditDebtText) ?? 0
        return max(0, limit - debt)
    }

    private var maxFractionDigitsForInput: Int {
        isMarketInvestment ? 8 : 2
    }

    private func plainAmountForInput(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigitsForInput
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }

    private func parseAmount(_ text: String) -> Double? {
        AmountInputFormatter.parse(text)
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

    private func setupInitialValues() {
        guard let info = accountInfo else { return }
        if isCreditCard, let card = currentCreditCard {
            if creditLimitText.isEmpty {
                creditLimitText = plainAmountForInput(card.creditLimit ?? 0)
            }
            if creditDebtText.isEmpty {
                let debt = max(0, (card.creditLimit ?? 0) - card.balance)
                creditDebtText = plainAmountForInput(debt)
            }
            return
        }
        if amountText.isEmpty {
            amountText = plainAmountForInput(currentEditableValue(fallbackAmount: info.amount))
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
            return marketInvestment?.category == .crypto ? "Количество монет" : "Количество"
        }
        return isCreditCard ? "Задолженность" : "Сумма"
    }

    private func valueSuffix(for info: (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool)) -> String {
        if isMarketInvestment {
            return marketInvestment?.category == .crypto ? "мон." : "шт."
        }
        return info.currency
    }

    private func currentEditableValue(fallbackAmount: Double) -> Double {
        if let investment = marketInvestment {
            return investment.marketQuantity ?? 0
        }
        return fallbackAmount
    }
}
