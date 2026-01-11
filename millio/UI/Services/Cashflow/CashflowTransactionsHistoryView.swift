//
//  CashflowTransactionsHistoryView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

struct CashflowTransactionsHistoryView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if viewModel.state.filteredTransactions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 64))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Text("Нет операций")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text("Добавьте первую операцию")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.state.filteredTransactions) { transaction in
                                CashflowTransactionRow(
                                    transaction: transaction,
                                    viewModel: viewModel
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("История операций")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}

// MARK: - Cashflow Transaction Row

private struct CashflowTransactionRow: View {
    let transaction: CashflowTransaction
    @ObservedObject var viewModel: CashflowViewModel
    
    var body: some View {
        Button {
            viewModel.handle(.editTransaction(transaction))
        } label: {
            HStack(spacing: 16) {
                // Иконка типа транзакции
                Image(systemName: transaction.transactionType.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: getGradientColors(),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    // Категория или тип
                    Text(getCategoryName())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    // Дата
                    Text(formatDate(transaction.transactionDate))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    // Карта или перевод
                    if let cardName = getCardName() {
                        Text(cardName)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Сумма
                    Text(formatAmount(transaction.amount))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            transaction.transactionType == .expense ? AppColors.error : AppColors.textPrimary
                        )
                    
                    // Валюта
                    Text(transaction.currency)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.handle(.deleteTransaction(transaction))
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }
    
    private func getGradientColors() -> [Color] {
        switch transaction.transactionType {
        case .income:
            return AppColors.incomeGradient
        case .expense:
            return AppColors.expenseGradient
        case .transfer:
            return AppColors.cashflowGradient
        case .exchange:
            return AppColors.coursesGradient
        }
    }
    
    private func getCategoryName() -> String {
        switch transaction.transactionType {
        case .income:
            return transaction.incomeCategory?.displayName ?? "Доход"
        case .expense:
            return transaction.expenseCategory?.displayName ?? "Расход"
        case .transfer:
            return "Перевод"
        case .exchange:
            if let fromCurrency = transaction.exchangeFromCurrency,
               let toCurrency = transaction.exchangeToCurrency {
                return "\(fromCurrency) → \(toCurrency)"
            }
            return "Обмен"
        }
    }
    
    private func getCardName() -> String? {
        switch transaction.transactionType {
        case .income, .expense:
            if let cardID = transaction.cardID,
               let card = viewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
                return card.name
            }
            return nil
            
        case .transfer:
            if let fromCardID = transaction.cardID,
               let toCardID = transaction.toCardID,
               let fromCard = viewModel.state.availableCards.first(where: { $0.cardUniqueID == fromCardID }),
               let toCard = viewModel.state.availableCards.first(where: { $0.cardUniqueID == toCardID }) {
                return "\(fromCard.name) → \(toCard.name)"
            }
            return nil
            
        case .exchange:
            if let fromAmount = transaction.exchangeFromAmount,
               let toAmount = transaction.exchangeToAmount,
               let fromCurrency = transaction.exchangeFromCurrency,
               let toCurrency = transaction.exchangeToCurrency {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.groupingSeparator = " "
                formatter.usesGroupingSeparator = true
                formatter.minimumFractionDigits = 2
                formatter.maximumFractionDigits = 2
                let fromFormatted = formatter.string(from: NSNumber(value: fromAmount)) ?? "0.00"
                let toFormatted = formatter.string(from: NSNumber(value: toAmount)) ?? "0.00"
                return "\(fromFormatted) \(fromCurrency) → \(toFormatted) \(toCurrency)"
            }
            return nil
        }
    }
    
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
}
