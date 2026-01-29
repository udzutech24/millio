//
//  CashflowView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

struct CashflowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CashflowViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                CashflowContentView(
                    viewModel: viewModel
                )
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CashflowViewModel(modelContext: modelContext)
            }
            // Перезагружаем данные при каждом появлении экрана
            viewModel?.handle(.loadCards)
            viewModel?.handle(.loadTransactions)
        }
    }
}

// MARK: - Cashflow Content View

private struct CashflowContentView: View {
    @ObservedObject var viewModel: CashflowViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Выбор периода
                    periodSelectionSection

                    // Статистика за период
                    periodStatsSection
                    
                    // Кнопки действий
                    actionButtonsSection
                    
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Кэшфлоу")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topToolbar }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTransactionEditor },
            set: { if !$0 { viewModel.handle(.hideTransactionEditor) } }
        )) {
            if let editingTransaction = viewModel.state.editingTransaction {
                CashflowTransactionEditorView(
                    viewModel: viewModel,
                    transaction: editingTransaction
                )
            } else if let creatingType = viewModel.state.creatingTransactionType {
                CashflowTransactionEditorView(
                    viewModel: viewModel,
                    transactionType: creatingType
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showPeriodSelector },
            set: { if !$0 { viewModel.handle(.hidePeriodSelector) } }
        )) {
            CashflowPeriodSelectorView(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTransactionsHistory },
            set: { if !$0 { viewModel.handle(.hideTransactionsHistory) } }
        )) {
            CashflowTransactionsHistoryView(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCurrencySelector },
            set: { if !$0 { viewModel.handle(.hideCurrencySelector) } }
        )) {
            CashflowCurrencySelectorView(viewModel: viewModel)
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Кнопка Доход
            CashflowActionButton(
                accessibilityLabel: "Доход",
                icon: "plus",
                gradientColors: AppColors.incomeGradient
            ) {
                viewModel.handle(.addTransaction(.income))
            }
            
            // Кнопка Расход
            CashflowActionButton(
                accessibilityLabel: "Расход",
                icon: "minus",
                gradientColors: AppColors.expenseGradient
            ) {
                viewModel.handle(.addTransaction(.expense))
            }
            
            // Кнопка Перевод
            CashflowActionButton(
                accessibilityLabel: "Перевод",
                icon: "arrow.left.arrow.right",
                gradientColors: AppColors.cashflowGradient
            ) {
                viewModel.handle(.addTransaction(.transfer))
            }
        }
    }
    
    // MARK: - Period Stats Section
    
    private var periodStatsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Доходы
                VStack(alignment: .leading, spacing: 8) {
                    Text("Заработано")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatAmount(viewModel.state.totalIncome))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.incomeGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        }
                )
                
                // Расходы
                VStack(alignment: .leading, spacing: 8) {
                    Text("Потрачено")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatAmount(viewModel.state.totalExpense))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.expenseGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.expenseGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        }
                )
            }
            
            // Баланс
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Баланс")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatAmount(viewModel.state.periodBalance))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(
                                viewModel.state.periodBalance >= 0 ?
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    colors: AppColors.expenseGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                
                Spacer()
                
                if viewModel.state.periodBalance != 0 {
                    Image(systemName: viewModel.state.periodBalance >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            viewModel.state.periodBalance >= 0 ?
                            LinearGradient(
                                colors: AppColors.incomeGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: AppColors.expenseGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
    }
    
    // MARK: - Period Selection Section
    
    private var periodSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Период")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    PeriodChip(
                        title: "Месяц",
                        isSelected: viewModel.state.chartPeriod == .month,
                        action: {
                            viewModel.handle(.setChartPeriod(.month))
                        }
                    )
                    
                    PeriodChip(
                        title: "Квартал",
                        isSelected: viewModel.state.chartPeriod == .quarter,
                        action: {
                            viewModel.handle(.setChartPeriod(.quarter))
                        }
                    )
                    
                    PeriodChip(
                        title: "Год",
                        isSelected: viewModel.state.chartPeriod == .year,
                        action: {
                            viewModel.handle(.setChartPeriod(.year))
                        }
                    )
                    
                    PeriodChip(
                        title: getSpecificPeriodTitle(),
                        isSelected: viewModel.state.chartPeriod == .specificMonth ||
                                   viewModel.state.chartPeriod == .specificQuarter ||
                                   viewModel.state.chartPeriod == .specificYear ||
                                   viewModel.state.chartPeriod == .custom,
                        action: {
                            viewModel.handle(.showPeriodSelector)
                        }
                    )
                }
                .padding(.horizontal, 4)
            }
            
            let range = viewModel.currentDateRange()
            Text("\(formatPeriod(range.0)) — \(formatPeriod(range.1))")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.3))
        )
    }
    
    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    viewModel.handle(.showCurrencySelector)
                } label: {
                    Image(systemName: "rublesign.circle.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Выбор валюты отображения")
                
                Button {
                    viewModel.handle(.showTransactionsHistory)
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("История операций")
            }
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
    
    private func formatPeriod(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
    
    private func getSpecificPeriodTitle() -> String {
        switch viewModel.state.chartPeriod {
        case .specificMonth:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: viewModel.state.selectedMonth)
        case .specificQuarter:
            let calendar = Calendar.current
            let month = calendar.component(.month, from: viewModel.state.selectedQuarter)
            let quarter = (month - 1) / 3 + 1
            let year = calendar.component(.year, from: viewModel.state.selectedQuarter)
            return "Q\(quarter) \(year)"
        case .specificYear:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            return formatter.string(from: viewModel.state.selectedYear)
        case .custom:
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM"
            return "\(formatter.string(from: viewModel.state.customStartDate)) - \(formatter.string(from: viewModel.state.customEndDate))"
        default:
            return "Выбрать период"
        }
    }
}

// MARK: - Period Chip

private struct PeriodChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : AppColors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(
                                colors: AppColors.cashflowGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                )
                .clipShape(Capsule())
        }
    }
}

// MARK: - Cashflow Action Button

private struct CashflowActionButton: View {
    let accessibilityLabel: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 2
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
