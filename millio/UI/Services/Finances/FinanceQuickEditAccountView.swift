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
    
    var isCreditCard: Bool {
        if account.accountType == .card,
           let card = viewModel.state.availableCards.first(where: { $0.cardUniqueID == account.accountID }),
           card.cardType == .credit {
            return true
        }
        return false
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
                                // Инициализируем значение при первом появлении
                                if amountText.isEmpty {
                                    amountText = plainAmountForInput(currentEditableValue(fallbackAmount: info.amount))
                                }
                                // Автоматически устанавливаем фокус на поле ввода
                                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
                                isAmountFieldFocused = true
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.black.opacity(0.3))
                            )
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                        
                        // Кнопка сохранения
                        Button {
                            saveAmount()
                        } label: {
                            Text("Сохранить")
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
                        .disabled(isLoading || !isValidAmount)
                        .opacity(isLoading || !isValidAmount ? 0.6 : 1.0)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(isMarketInvestment ? "Редактирование количества" : "Редактирование суммы")
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
    }
    
    private var isValidAmount: Bool {
        guard let amount = parseAmount(amountText) else {
            return false
        }
        return amount >= 0
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
    
    private func saveAmount() {
        guard let amount = parseAmount(amountText), amount >= 0 else {
            return
        }
        
        isLoading = true
        viewModel.handle(.updateAccountAmount(account, amount))
        isLoading = false
        dismiss()
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
