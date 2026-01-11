//
//  PaymentSheet.swift
//  millio
//
//  Created by Александр Сидоркин on 11.01.2026.
//

import SwiftUI

// MARK: - Payment Sheet

struct PaymentSheet: View {
    @ObservedObject var viewModel: CreditViewModel
    let credit: Credit
    @Environment(\.dismiss) private var dismiss
    
    @State private var paymentAmountText: String = ""
    @State private var reduceTerm: Bool = true // true = уменьшить срок, false = уменьшить платеж
    @State private var paymentDate: Date = Date()
    @State private var note: String = ""
    
    // Предварительный расчет
    @State private var newTermMonths: Int = 0
    @State private var newMonthlyPayment: Double = 0.0
    @State private var newRemainingAmount: Double = 0.0
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        Text("Остаток долга: \(formatBalance(credit.remainingAmount)) \(credit.currency)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Текущий статус")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        TextField("Сумма платежа", text: Binding(
                            get: { formatNumberForDisplay(paymentAmountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                paymentAmountText = normalized
                                calculatePreview()
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        
                        DatePicker("Дата платежа", selection: $paymentDate, displayedComponents: .date)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Примечание (необязательно)", text: $note)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Параметры платежа")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        Picker("Стратегия досрочного погашения", selection: $reduceTerm) {
                            Text("Уменьшить срок кредита").tag(true)
                            Text("Уменьшить ежемесячный платеж").tag(false)
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .onChange(of: reduceTerm) { _, _ in
                            calculatePreview()
                        }
                    } header: {
                        Text("Стратегия")
                            .foregroundStyle(AppColors.textSecondary)
                    } footer: {
                        Text(reduceTerm ? 
                             "Ежемесячный платеж останется прежним, но срок кредита уменьшится." :
                             "Срок кредита останется прежним, но ежемесячный платеж уменьшится.")
                            .foregroundStyle(AppColors.textTertiary)
                            .font(.system(size: 12))
                    }
                    
                    // Предварительный расчет
                    if !paymentAmountText.isEmpty, let amount = parseNumber(paymentAmountText), amount > 0 {
                        Section {
                            if amount >= credit.remainingAmount {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Кредит будет полностью погашен")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.creditsGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            } else {
                                if reduceTerm {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Новый срок:")
                                                .foregroundStyle(AppColors.textTertiary)
                                            Spacer()
                                            Text("\(newTermMonths) мес.")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                        }
                                        
                                        HStack {
                                            Text("Ежемесячный платеж:")
                                                .foregroundStyle(AppColors.textTertiary)
                                            Spacer()
                                            Text("\(formatBalance(credit.monthlyPayment)) \(credit.currency)")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                        }
                                        
                                        HStack {
                                            Text("Остаток после платежа:")
                                                .foregroundStyle(AppColors.textTertiary)
                                            Spacer()
                                            Text("\(formatBalance(newRemainingAmount)) \(credit.currency)")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                        }
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Новый ежемесячный платеж:")
                                                .foregroundStyle(AppColors.textTertiary)
                                            Spacer()
                                            Text("\(formatBalance(newMonthlyPayment)) \(credit.currency)")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                        }
                                        
                                        HStack {
                                            Text("Срок кредита:")
                                                .foregroundStyle(AppColors.textTertiary)
                                            Spacer()
                                            Text("\(credit.monthsRemaining) мес.")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                        }
                                        
                                        HStack {
                                            Text("Остаток после платежа:")
                                                .foregroundStyle(AppColors.textTertiary)
                                            Spacer()
                                            Text("\(formatBalance(newRemainingAmount)) \(credit.currency)")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Предварительный расчет")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Внести платеж")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Внести") {
                        makePayment()
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
            }
            .onAppear {
                calculatePreview()
            }
        }
    }
    
    private var isValid: Bool {
        guard let amount = parseNumber(paymentAmountText),
              amount > 0,
              amount <= credit.remainingAmount else {
            return false
        }
        return true
    }
    
    private func calculatePreview() {
        guard let amount = parseNumber(paymentAmountText),
              amount > 0,
              amount <= credit.remainingAmount else {
            newTermMonths = 0
            newMonthlyPayment = 0.0
            newRemainingAmount = credit.remainingAmount
            return
        }
        
        newRemainingAmount = credit.remainingAmount - amount
        
        if reduceTerm {
            // Уменьшаем срок
            newTermMonths = credit.calculateNewTermAfterEarlyPayment(earlyPaymentAmount: amount)
            newMonthlyPayment = credit.monthlyPayment
        } else {
            // Уменьшаем платеж
            newMonthlyPayment = credit.calculateNewPaymentAfterEarlyPayment(earlyPaymentAmount: amount)
            newTermMonths = credit.monthsRemaining
        }
    }
    
    private func makePayment() {
        guard let amount = parseNumber(paymentAmountText),
              amount > 0 else {
            return
        }
        
        viewModel.handle(.makePayment(amount: amount, reduceTerm: reduceTerm, credit: credit))
        dismiss()
    }
    
    // MARK: - Helpers
    
    private func parseNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    private func formatNumberForDisplay(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        guard let number = parseNumber(text) else { return text }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        let normalized = text.replacingOccurrences(of: " ", with: "")
        let hasDecimal = normalized.contains(".") || normalized.contains(",")
        if !hasDecimal {
            formatter.maximumFractionDigits = 0
        }
        
        return formatter.string(from: NSNumber(value: number)) ?? text
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }
}
